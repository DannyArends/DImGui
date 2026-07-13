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

/** Material-SSBO layout: slot i (0..ResourceType.max) is material i; item templates follow with 2 slots each (empty, filled). */
enum uint TEMPLATE_MAT_BASE = ResourceType.max + 1;
@nogc pure uint templateMat(ItemTemplate t, bool filled = false) nothrow { return TEMPLATE_MAT_BASE + 2 * (cast(uint)t - 1) + (filled ? 1 : 0); }

/** Resource-mesh prefix — one mesh per ResourceType; fully determined at compile time. */
static immutable Mesh[] resourcePrefix = iota(cast(int)ResourceType.max + 1).map!(tt => Mesh([0, 0], tt)).array;

void injectResourceMeshes(ref GameApp app, uint nMaterials = TEMPLATE_MAT_BASE + (2 * ItemTemplate.max)) {
  app.meshes.length = resourcePrefix.length;
  app.meshes[0 .. resourcePrefix.length] = resourcePrefix;
  if(app.materials.length < nMaterials) app.materials.length = nMaterials;
}

void updateMaterials(ref GameApp app) {
  foreach (tt; 0 .. TEMPLATE_MAT_BASE) {
    auto ttype = cast(ResourceType)tt;
    app.materials[tt].tid = app.textures.idx(resourceData(ttype).tex3D);
    if(resourceData(ttype).meshName != "Blocks"){ app.materials[tt].nid = app.textures.idx(resourceData(ttype).tex3D.replace("_base", "_normal")); }
  }
  foreach (ti; 1 .. cast(int)ItemTemplate.max + 1) {
    auto t = cast(ItemTemplate)ti;
    app.materials[templateMat(t)].tid = app.textures.idx(templateData(t).tex);
    if(templateData(t).texFilled.length){ app.materials[templateMat(t, true)].tid = app.textures.idx(templateData(t).texFilled); }
  }
}

