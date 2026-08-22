/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 * All CTFE raw template structs. Engine-only (imports lsystem/color, never game/raws) so raws' CTFE cannot cycle.
 */

import phobos;

import color : Colors;
import ctfe : composedEnum, enumFromTag, EnumRule;
import lsystem : Effect, Rule, Symbol;
import turtlegfx : AnimClip;

enum WorkshopUse : ubyte { None, Required, Preferred }

mixin(enumFromTag(import("data/raws/items.txt"), "ITEM", "ItemTemplate", "None"));
mixin(enumFromTag(import("data/raws/substance.txt"), "SUBSTANCE", "Substance", "None"));

mixin(composedEnum("Source", "None",
  [EnumRule("TILE"), EnumRule("FEATURE")],
  import("data/raws/tiles.txt"), import("data/raws/features.txt")));

// ResourceType = every tile, then <Feature><Substance> per brush (grouped by FEATURE, brush field 3)
mixin(composedEnum("ResourceType", "",
  [EnumRule("TILE"), EnumRule("BRUSH", "FEATURE", 1, "substance")],
  import("data/raws/tiles.txt"), import("data/raws/features.txt")));

enum size_t RESOURCE_COUNT = ResourceType.max + 1;   /// Number of ResourceType members (variants)
alias SpawnMask = bool[RESOURCE_COUNT];

/** Per-species entity template: pawn behaviour + an L-system body baked into an OpenAsset. */
struct RawT {
  string name;                                    /// Species name, e.g. "Dwarf"
  ResourceType[] spawnOn;                         /// tiles this entity spawns on (empty = not wild-spawned, e.g. Dwarf)
  float noiseThreshold = 0.92f;                   /// hash-noise spawn gate (higher = rarer)
  uint hashSeed1, hashSeed2;                      /// per-species spawn hash seeds
  uint hashMod, hashRem;                          /// optional hash bucketing (0 = unused)
  float moveSpeed = 2.0f;                         /// Tiles per second
  float hungerDecay = 0.0f, thirstDecay = 0.0f;   /// Need growth per tick
  string diet;                                    /// Substance/type eaten (empty = none)
  float scale = 1.0f, scaleVariance = 0.0f;       /// Instance scale + per-spawn variance
  float offsetY = 0.0f;                           /// Vertical render offset to seat on the tile
  float hop = 0.0f;                               /// Vertical render offset to seat on the tile
  string axiom = "B";                             /// L-system start symbol(s)
  Rule[] rules;                                   /// L-system production rules (empty = axiom as-is)
  AnimClip[] clips;                               /// animation L-systems, walked in time -> keyframe tracks
  LSystemBrushT[] brushes;                        /// Symbol -> mesh brushes (entities ignore the material fields)
  LSystemBoneT[] bones;                           /// meshless skeleton joints
  uint heightMin = 1, heightMax = 1;              /// L-system growth budget range (feature height)
  float tilePenalty = 0.0f;                       /// movement penalty on the feature's footprint tiles
  float progressRate = 0.25f;                     /// harvest progress per tick
  string interaction;                             /// interaction verb gate (empty = none)
  string sound;                                   /// harvest sound
}

/** A meshless, poseable skeleton joint: a named frame at the cursor. */
struct LSystemBoneT {
  string symbol;                                  /// grammar symbol (meshless, poseable joint)
}



struct Tex { string role; string name; }

/** Texture name for a role, "" if unset. */
@nogc pure string texOf(const Tex[] textures, string role) nothrow {
  foreach(ref t; textures) if(t.role == role) { return(t.name); }
  return("");
}

Tex[] parseTextures(string v) pure {
  Tex[] r;
  if(v.length >= 2 && v[0] == '{' && v[$ - 1] == '}') { v = v[1 .. $ - 1]; }
  foreach(pair; v.split(";")) {
    immutable e = pair.indexOf('=');
    if(e > 0) { r ~= Tex(pair[0 .. e], pair[e + 1 .. $]); }
  }
  return(r);
}

/** Render/item fields common to renderable raws (resources, item templates, ...). */
mixin template Renderable() {
  string mesh = "Cube";         /// geometry (tinted/textured at use time)
  Tex[] textures;               /// Role to Texture bindings; open-ended set of roles
  Colors color = Colors.white;  /// Color
  float[3] size = [0.1f, 1.0f, 0.1f];             /// local half-extents [radius(X), length(Y), depth(Z)]
  float[3] offset = [0.0f, 0.0f, 0.0f];           /// local-frame draw offset [right, up, forward] (entities: place a detail precisely)
  int maxStack = 1;             /// stack size when carried
  float food = 0.0f;            /// nutrition/edibility (0 => inedible)
}

/** L-system brush: one grammar symbol. */
struct LSystemBrushT {
  string symbol;                                  /// grammar symbol, e.g. 'Y' or 'I'
  mixin Renderable;
  Substance substance;                            /// Substance drawn
  bool render = true;                             /// draw on the growing feature? false = harvest-only (a drop)
  bool tint = false;                              /// tint with the entity's per-instance colour instead of `color`
  float taper = 0.0f;                             /// radius growth per unit of the module parameter n (0 = uniform)
}

/** A tile/feature variant = substance @ source; the row backing each ResourceType member. */
struct ResourceT {
  string name = "None";         /// Raw identifier
  mixin Renderable;
  Substance substance;          /// variant match key
  Source source;                /// which tile/feature produced it
  float traverse = 0.0f;        /// walk cost; 0 => impassable
  bool build = false;           /// may be placed/built with
}

/** A crafted item template (shape) parsed from items.txt into itemTemplateTable. */
struct ItemTemplateT {
  string name = "None";         /// Raw identifier
  mixin Renderable;
  Substance[] accepts;          /// material's allowed substances; empty => any
  Substance[] holds;            /// contents' allowed substances; empty => not a container
  uint capacity = 0;            /// max content units (0 => not a container)
}

struct Ingredient { Substance cls; ItemTemplate item; uint count = 1; }

/** One output line: a raw material (shape == None, `type` names the ResourceType) OR a crafted item
 *  (shape != None) whose material is inherited from the consumed input of class `materialFrom`. */
struct Product { ItemTemplate shape; ResourceType type; Substance materialFrom; float chance = 1.0f; uint count = 1; }

struct Reaction {
  string name, verb, skill;
  float progressRate = 1.0f;
  WorkshopUse workshop;
  Ingredient[] inputs;
  Product[] outputs;
}

struct SpawnGroup(size_t N){ size_t[N] animalIndices; ubyte count; }

/** One terrain height band: an upper threshold and the resources eligible at that height. */
struct HeightBand { float threshold; ResourceType[] results; }

