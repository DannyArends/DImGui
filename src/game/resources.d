/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : resourceType, itemOf;
import io : dir, fixPath;
import raws : RESOURCE_COUNT;
import surface : toRGBA;
import textures : transferTextureAsync, idx;

struct ClassVal { ubyte cls; float value = 0.0f; }   // cls = cast(ubyte)Substance (legacy; unused since variants carry a single substance)

struct ResourceT {
  string name = "None", meshName = "Blocks", tex3D = "", tex2D = "";
  float scale = 1.0f;
  float offsetY = 0.0f;                     /// vertical render offset (world units) for model-backed drops
  Colors color = Colors.white;
  ubyte substance = 0;                      /// cast(ubyte)Substance — the variant's match key (was the name-class)
  float traverse = 0.0f;                    /// walk cost; 0 => impassable (liquids)
  bool build = false;                       /// may be placed/built with
  int maxStack = 1;                         /// stack size when carried as a raw item
}

/** An item template = a shape/type (Axe, Cup, Barrel, Bin). A concrete item is (template x material).
 *  accepts/holds are cast(ubyte)Substance to dodge the same cross-module enum forward-ref as ClassVal. */
struct ItemTemplateT {
  string name = "None";
  string mesh = "Cube";    /// shape geometry (tinted/textured by material at use time)
  string tex3D = "";       /// world texture (model atlas); empty => use `tex`
  string tex  = "";        /// template skin; empty => fall back to the material's texture
  string texFilled = "";   /// skin when the container holds contents (amount > 0); empty => use `tex`
  float scale = 1.0f;      /// render scale of the crafted item
  float offsetY = 0.0f;    /// vertical render offset (model units) for model-backed items
  ubyte[] accepts;         /// Substance the material may belong to; empty => any
  ubyte[] holds;           /// Substance the contents may belong to; empty => not a container
  uint capacity = 0;       /// max units of contents (0 => not a container; a cup = 1)
  int maxStack = 1;        /// stack size of the crafted item
  float food = 0.0f;       /// nutrition restored when eaten (0 => not edible)
}

/** A concrete item = (shape x material), optionally holding `amount` units of `contents`.
 *  shape == None => a raw material block (berry/flint/log/stone) keyed purely on `material`. */
struct Item {
  ItemTemplate shape    = ItemTemplate.None;   /// template (shape/type); None => raw material. ('template' is a D keyword, hence 'shape')
  ResourceType material = ResourceType.None;   /// the substance the item is made of
  ResourceType contents = ResourceType.None;   /// what a container currently holds (None => empty)
  uint amount = 0;                             /// units of `contents` held (0 => empty; a full cup = 1)
}

/** The substance (match key) of a variant. */
@nogc Substance substanceOf(ResourceType t) pure nothrow { return cast(Substance)resourceData(t).substance; }

/** A variant "has class c" iff its substance IS c (one substance per variant). */
@nogc bool hasClass(ResourceType t, Substance c) pure nothrow { return substanceOf(t) == c; }

/** Does an item satisfy a demand: an item template (want) if set, else a material of substance cls
 *  (restricted to raw blocks when `raw`, so crafted items never fill a build/ingredient demand). */
@nogc pure bool matchDemand(const Item it, Substance cls, ItemTemplate want, bool raw = true) nothrow {
  if(want != ItemTemplate.None) return it.shape == want;
  return (!raw || it.isRaw) && (cls == Substance.None || it.material.hasClass(cls));
}

/** Carried block ids satisfying a demand (want ? by template : by material substance; crafted allowed). */
auto carriedFor(ref GameApp app, ref Dwarf d, Substance cls, ItemTemplate want = ItemTemplate.None) {
  return d.carrying.filter!(id => app.world.drops.itemOf(id).matchDemand(cls, want, false));
}

// A variant's substance is its "class"; converting the other way picks a representative variant of that substance.
@nogc Substance toClass(ResourceType t) pure nothrow { return substanceOf(t); }
@nogc ResourceType toType(Substance c) pure nothrow {
  foreach(rt; EnumMembers!ResourceType) if(substanceOf(rt) == c) return rt;
  return ResourceType.None;
}

// Convenience field accessors (UFCS shims over the variant's own fields)
@nogc bool traversable(const ResourceType r) pure nothrow { return resourceData(r).traverse > 0.0f; }
@nogc bool buildable(const ResourceType r) pure nothrow { return resourceData(r).build; }
@nogc float cost(const ResourceType r) pure nothrow { return resourceData(r).traverse; }
@nogc int maxStack(const ResourceType r) pure nothrow { return resourceData(r).maxStack; }
@nogc pure bool isFood(const Item it) nothrow { return it.isCraft && templateData(it.shape).food > 0.0f; }
@nogc pure float foodValue(const Item it) nothrow { return it.isCraft ? templateData(it.shape).food : 0.0f; }

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

/** Material-SSBO layout: slot i (0..RESOURCE_COUNT) is material i; item templates follow with 2 slots each (empty, filled). */
@nogc pure uint templateMat(ItemTemplate t, bool filled = false) nothrow { return cast(uint)(RESOURCE_COUNT) + 2 * (cast(uint)t - 1) + (filled ? 1 : 0); }

/** Resource-mesh prefix — one mesh per ResourceType; fully determined at compile time. */
static immutable Mesh[] resourcePrefix = iota(cast(int)RESOURCE_COUNT).map!(tt => Mesh([0, 0], tt)).array;

void injectResourceMeshes(ref GameApp app, uint minMaterials = RESOURCE_COUNT + (2 * ItemTemplate.max)) {
  app.meshes.length = resourcePrefix.length;
  app.meshes[0 .. resourcePrefix.length] = resourcePrefix;
  if(app.materials.length < minMaterials) app.materials.length = minMaterials;
}

void updateMaterials(ref GameApp app) {
  foreach (tt; 0 .. RESOURCE_COUNT) {
    auto ttype = cast(ResourceType)tt;
    app.materials[tt].tid = app.textures.idx(resourceData(ttype).tex3D);
    if(resourceData(ttype).meshName != "Blocks"){ app.materials[tt].nid = app.textures.idx(resourceData(ttype).tex3D.replace("_base", "_normal")); }
  }
  foreach (ti; 1 .. cast(int)ItemTemplate.max + 1) {
    auto t = cast(ItemTemplate)ti;
    int tid = app.textures.idx(templateData(t).tex3D);   // 3D objects always use tex3D; tex/texFilled are 2D-display only
    app.materials[templateMat(t)].tid = tid;
    app.materials[templateMat(t, true)].tid = tid;
  }
}

