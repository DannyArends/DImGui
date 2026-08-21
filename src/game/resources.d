/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : itemOf;
import textures : idx;

/** A concrete item = (shape x material), optionally holding `amount` units of `contents`.
 *  shape == None => a raw material block (berry/flint/log/stone) keyed purely on `material`. */
struct Item {
  ItemTemplate shape    = ItemTemplate.None;   /// template (shape/type); None => raw material. ('template' is a D keyword, hence 'shape')
  ResourceType material = ResourceType.None;   /// the substance the item is made of
  ResourceType contents = ResourceType.None;   /// what a container currently holds (None => empty)
  uint amount = 0;                             /// units of `contents` held (0 => empty; a full cup = 1)
}

/** Turtle config (angles + gap + brush->Symbol alphabet) for a raw's brushes. Vegetation brushes carry a
    substance -> resolved to a resource variant's material + colour; pawn brushes use their literal colour.
    renderOnly skips harvest-only brushes (features draw a subset; harvest needs every brush's position). */
TurtleConfig rawConfig(ref const RawT r, bool renderOnly = false) {
  TurtleConfig cfg;
  foreach(ref br; r.brushes) {
    if(renderOnly && !br.render) continue;
    immutable bool subst = br.substance != Substance.init;
    immutable int mat = subst ? cast(int)variantOf(br.substance, r.name.to!Source) : -1;
    immutable float[4] col = subst ? resourceTable[mat].color : br.color;
    immutable float dep = subst ? -1.0f : br.depth;
    cfg.alpha[br.symbol] = Symbol(Effect.brush, mat, br.radius, br.length, col, br.offset, dep, br.taper, br.jitterA, br.jitterL);
  }
  return cfg;
}

/** Does an item satisfy a demand: an item template (want) if set, else a material of substance cls
 *  (restricted to raw blocks when `raw`, so crafted items never fill a build/ingredient demand). */
@nogc pure bool matchDemand(const Item it, Substance cls, ItemTemplate want, ResourceType type = ResourceType.None, bool raw = true) nothrow {
  if(want != ItemTemplate.None) return it.shape == want;
  if(type != ResourceType.None) return it.isRaw && it.material == type;   // exact variant (Building)
  return (!raw || it.isRaw) && (cls == Substance.None || resourceTable[it.material].substance == cls);
}

/** Carried block ids satisfying a demand (want ? by template : by material substance; crafted allowed). */
auto carriedFor(ref GameApp app, ref Dwarf d, Substance cls, ItemTemplate want = ItemTemplate.None, ResourceType type = ResourceType.None) {
  return d.carrying.filter!(id => app.world.drops.itemOf(id).matchDemand(cls, want, type, false));
}

// Convenience field accessors (UFCS shims over the variant's own fields)
@nogc bool traversable(const ResourceType r) pure nothrow { return resourceTable[r].traverse > 0.0f; }
@nogc bool buildable(const ResourceType r) pure nothrow { return resourceTable[r].build; }
@nogc float cost(const ResourceType r) pure nothrow { return resourceTable[r].traverse; }
@nogc int maxStack(const ResourceType r) pure nothrow { return resourceTable[r].maxStack; }
@nogc bool isFood(const Item it) pure nothrow { return it.foodValue() > 0.0f; }
@nogc float foodValue(const Item it) pure nothrow {
  return it.isCraft ? itemTemplateTable[it.shape].food : it.material != ResourceType.None ? resourceTable[it.material].food : 0.0f;
}
/** The source (origin tile/feature) of a variant, and the reverse lookup (substance @ source -> variant). */
@nogc ResourceType variantOf(Substance s, Source src) pure nothrow {
  foreach(rt; EnumMembers!ResourceType) if(rt != ResourceType.None && resourceTable[rt].substance == s && resourceTable[rt].source == src) return rt;
  return ResourceType.None;
}

// Item = (shape template x material [+ contents]); accessors compute everything from the pair at use time.
@nogc pure bool isRaw(const Item it) nothrow { return it.shape == ItemTemplate.None; }
@nogc pure bool isCraft(const Item it) nothrow { return it.shape != ItemTemplate.None; }
@nogc pure bool isContainer(const Item it) nothrow { return itemTemplateTable[it.shape].capacity > 0; }
@nogc pure bool isFull(const Item it) nothrow { return it.amount >= itemTemplateTable[it.shape].capacity; }
@nogc pure int itemStack(const Item it) nothrow { return it.isCraft ? itemTemplateTable[it.shape].maxStack : it.material.maxStack; }

// Cup container predicates (Water fill mechanic; generalises to barrels/bins later)
@nogc pure bool isCup(const Item it) nothrow { return it.shape == ItemTemplate.Cup; }
@nogc pure bool isEmptyCup(const Item it) nothrow { return it.isCup && it.contents == ResourceType.None; }
@nogc pure bool isWaterCup(const Item it) nothrow { return it.isCup && it.contents == ResourceType.Water; }

/** Name to display for an item */
string itemName(const Item it) {
  if(!it.isCraft) return resourceTable[it.material].name;
  string n = resourceTable[it.material].name ~ " " ~ itemTemplateTable[it.shape].name;
  if(it.contents != ResourceType.None) n ~= " of " ~ resourceTable[it.contents].name;
  return n;
}

/** Texture to display for an item: template skin (filled variant when holding contents), else the raw material's 2D texture. */
string itemTex(const Item it) {
  if(!it.isCraft) return resourceTable[it.material].tex2D;
  auto t = itemTemplateTable[it.shape];
  return (it.amount > 0 && t.texFilled.length) ? t.texFilled : t.tex;
}

/** Wrap a raw material as an Item (shape == None). The default way to build a material-only Item. */
@nogc pure Item toItem(ResourceType m) nothrow { return Item(ItemTemplate.None, m); }

/** Material-SSBO layout: slot i (0..RESOURCE_COUNT) is material i; item templates follow with 2 slots each (empty, filled). */
@nogc pure uint templateMat(ItemTemplate t, bool filled = false) nothrow {
  return cast(uint)(RESOURCE_COUNT) + 2 * (cast(uint)t - 1) + (filled ? 1 : 0);
}

void injectResourceMeshes(ref GameApp app, uint minMaterials = RESOURCE_COUNT + (2 * ItemTemplate.max)) {
  if(app.materials.length < minMaterials){ app.materials.length = minMaterials; }
}

void updateMaterials(ref GameApp app) {
  foreach (tt; 0 .. RESOURCE_COUNT) {
    auto ttype = cast(ResourceType)tt;
    app.materials[tt].tid = app.textures.idx(resourceTable[ttype].tex3D);
    if(resourceTable[ttype].mesh != "Blocks"){ app.materials[tt].nid = app.textures.idx(resourceTable[ttype].tex3D.replace("_base", "_normal")); }
  }
  foreach (ti; 1 .. cast(int)ItemTemplate.max + 1) {
    auto t = cast(ItemTemplate)ti;
    int tid = app.textures.idx(itemTemplateTable[t].tex3D);   // 3D objects always use tex3D; tex/texFilled are 2D-display only
    app.materials[templateMat(t)].tid = tid;
    app.materials[templateMat(t, true)].tid = tid;
  }
}

