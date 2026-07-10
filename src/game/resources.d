/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import io : dir, fixPath;
import textures : transferTextureAsync, idx, toRGBA;

struct ClassVal { ubyte cls; float value = 0.0f; }   // cls = cast(ubyte)ResourceClass — avoids the cross-module enum forward-ref

struct ResourceT {
  string name = "None", meshName = "Blocks", tex3D = "", tex2D = "";
  float scale = 1.0f;
  Colors color = Colors.white;
  ClassVal[] classes;
}

/** An item template = a shape/type (Axe, Cup, Barrel, Bin). A concrete item is (template x material).
 *  accepts/holds are cast(ubyte)ResourceClass to dodge the same cross-module enum forward-ref as ClassVal. */
struct ItemTemplateT {
  string name = "None";
  string mesh = "Cube";   /// shape geometry (tinted/textured by material at use time)
  string tex  = "";        /// template skin; empty => fall back to the material's texture
  string texFilled = "";   /// skin when the container holds contents (amount > 0); empty => use `tex`
  float scale = 1.0f;      /// render scale of the crafted item
  ubyte[] accepts;         /// ResourceClass the material may belong to; empty => any
  ubyte[] holds;           /// ResourceClass the contents may belong to; empty => not a container
  uint capacity = 0;       /// max units of contents (0 => not a container; a cup = 1)
  int maxStack = 1;        /// stack size of the crafted item
}

/** A concrete item = (shape x material), optionally holding `amount` units of `contents`.
 *  shape == None => a raw material block (berry/flint/log/stone) keyed purely on `material`. */
struct Item {
  ItemTemplate shape    = ItemTemplate.None;   /// template (shape/type); None => raw material. ('template' is a D keyword, hence 'shape')
  ResourceType material = ResourceType.None;   /// the substance the item is made of
  ResourceType contents = ResourceType.None;   /// what a container currently holds (None => empty)
  uint amount = 0;                             /// units of `contents` held (0 => empty; a full cup = 1)
}

// Primitives on ResourceT
@nogc bool hasClass(ResourceType t, ResourceClass c) pure nothrow {
  foreach(cv; resourceData(t).classes) { if(cv.cls == cast(ubyte)c) { return true; } } return false;
}
@nogc float classVal(ResourceType t, ResourceClass c) pure nothrow {
  foreach(cv; resourceData(t).classes) { if(cv.cls == cast(ubyte)c) { return cv.value; } } return 0.0f;
}

ResourceClass toClass(ResourceType t) { return t.to!string.to!ResourceClass; }
ResourceType toType(ResourceClass c) { return c.to!string.to!ResourceType; }

// Convenience field accessors (UFCS shims over classes)
@nogc bool traversable(const ResourceType r) pure nothrow { return r.hasClass(ResourceClass.Traversable); }
@nogc bool buildable(const ResourceType r) pure nothrow { return r.hasClass(ResourceClass.Buildable); }
@nogc float cost(const ResourceType r) pure nothrow { return r.classVal(ResourceClass.Traversable); }
@nogc int maxStack(const ResourceType r) pure nothrow { return cast(int)r.classVal(ResourceClass.Item); }
@nogc bool isFood(const ResourceType r) pure nothrow { return r.hasClass(ResourceClass.Food); }
@nogc float foodValue(const ResourceType r) pure nothrow { return r.classVal(ResourceClass.Food); }

// Item = (shape template x material [+ contents]); accessors compute everything from the pair at use time.
@nogc pure bool isRaw(const Item it) nothrow { return it.shape == ItemTemplate.None; }
@nogc pure bool isCraft(const Item it) nothrow { return it.shape != ItemTemplate.None; }
@nogc pure bool isContainer(const Item it) nothrow { return templateData(it.shape).capacity > 0; }
@nogc pure bool isFull(const Item it) nothrow { return it.amount >= templateData(it.shape).capacity; }
@nogc pure int itemStack(const Item it) nothrow { return it.isCraft ? templateData(it.shape).maxStack : it.material.maxStack; }

// Cup container predicates (Water fill mechanic; generalises to barrels/bins later)
@nogc pure bool isCup(const Item it) nothrow { return it.shape == ItemTemplate.Cup; }
@nogc pure bool isEmptyCup(const Item it) nothrow { return it.isCup && it.contents == ResourceType.None; }
@nogc pure bool isWaterCup(const Item it) nothrow { return it.isCup && it.contents == ResourceType.Water; }

/** Name to display for an item */
string itemName(const Item it) {
  if(!it.isCraft) return resourceData(it.material).name;
  string n = resourceData(it.material).name ~ " " ~ templateData(it.shape).name;
  if(it.contents != ResourceType.None) n ~= " of " ~ resourceData(it.contents).name;
  return n;
}

/** Texture to display for an item: template skin (filled variant when holding contents), else the raw material's 2D texture. */
string itemTex(const Item it) {
  if(!it.isCraft) return resourceData(it.material).tex2D;
  auto t = templateData(it.shape);
  return (it.amount > 0 && t.texFilled.length) ? t.texFilled : t.tex;
}

/** Wrap a raw material as an Item (shape == None). The default way to build a material-only Item. */
@nogc pure Item toItem(ResourceType m) nothrow { return Item(ItemTemplate.None, m); }

void injectResourceMeshes(ref GameApp app) {
  app.meshes.length = 0;
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    app.world.resources[ttype] = cast(uint)app.meshes.length;
    if(app.materials.length <= tt) app.materials ~= Material();  // only add material once
    app.meshes ~= Mesh([0, 0], cast(int)tt);  // reuse existing material slot
  }
  if(!app.world.templatesInjected) {   // material slots are permanent; allocate once (this fn runs every frame)
    foreach (ti; 0 .. cast(int)ItemTemplate.max + 1) {
      auto t = cast(ItemTemplate)ti;
      if(t == ItemTemplate.None) continue;
      app.world.templateTex[t] = cast(uint)app.materials.length; app.materials ~= Material();
      if(templateData(t).texFilled.length) { app.world.templateTexFilled[t] = cast(uint)app.materials.length; app.materials ~= Material(); }
    }
    app.world.templatesInjected = true;
  }
}

void updateMaterials(ref GameApp app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    uint idx =  app.world.resources[ttype];
    app.materials[app.meshes[idx].mid].tid = app.textures.idx(resourceData(ttype).tex3D);
    if((resourceData(ttype).meshName != "Blocks")) {
      app.materials[app.meshes[idx].mid].nid = app.textures.idx(resourceData(ttype).tex3D.replace("_base", "_normal"));
    }
  }
  foreach (ti; 0 .. cast(int)ItemTemplate.max + 1) {
    auto t = cast(ItemTemplate)ti;
    if(t == ItemTemplate.None) continue;
    app.materials[app.world.templateTex[t]].tid = app.textures.idx(templateData(t).tex);
    if(templateData(t).texFilled.length) app.materials[app.world.templateTexFilled[t]].tid = app.textures.idx(templateData(t).texFilled);
  }
}

