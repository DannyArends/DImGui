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
  float facing = 0.0f;                            /// Yaw offset correcting the model's forward axis
  string axiom = "B";                             /// L-system start symbol(s)
  uint lsystemIter = 1;                           /// stochastic rewrite passes (>1 enables recursive limb rules)
  Rule[] rules;                                   /// L-system production rules (empty = axiom as-is)
  AnimClip[] clips;                               /// animation L-systems, walked in time -> keyframe tracks
  LSystemBrushT[] brushes;                        /// Symbol -> mesh brushes (entities ignore the material fields)
  float lsystemYaw = 25.0f;                       /// Yaw
  float lsystemPitch = 25.0f;                     /// Pitch
  float lsystemRoll = 25.0f;                      /// Roll
  float lsystemGap = 0.2f;                        /// f translation step (no draw)
  uint heightMin = 1, heightMax = 1;              /// L-system growth budget range (feature height)
  float tilePenalty = 0.0f;                       /// movement penalty on the feature's footprint tiles
  float progressRate = 0.25f;                     /// harvest progress per tick
  string interaction;                             /// interaction verb gate (empty = none)
  string sound;                                   /// harvest sound
}

/** L-system brush: one grammar symbol. */
struct LSystemBrushT {
  string symbol;                                /// grammar symbol, e.g. 'Y' or 'I'
  string mesh;                                  /// mesh name: primitive ("Cylinder") or model ("watermelon")
  Substance substance;                          /// Substance drawn
  string texture;                               /// per-instance texture for the drawn geometry
  float radius = 0.1f;                          /// local X/Z scale
  float length = 1.0f;                          /// local Y scale / segment length
  bool advance = true;                          /// move turtle forward after drawing
  float food = 0.0f;                            /// edibility of the produced substance (0 = inedible)
  bool render = true;                           /// draw on the growing feature? false = harvest-only (a drop)
  float[3] offset = [0.0f, 0.0f, 0.0f];         /// local-frame draw offset [right, up, forward] (entities: place a detail precisely)
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// per-brush vertex colour (entities)
  bool tint = false;                            /// tint with the entity's per-instance colour instead of `color`
  float depth = -1.0f;                          /// local Z scale; -1 = use radius (square section)
  float taper = 0.0f;                           /// radius growth per unit of the module parameter n (0 = uniform)
}

/** A tile/feature variant = substance @ source; the row backing each ResourceType member. */
struct ResourceT {
  string name = "None", mesh = "Blocks", tex3D = "", tex2D = "";
  float scale = 1.0f;
  float offsetY = 0.0f;                     /// vertical render offset (world units) for model-backed drops
  Colors color = Colors.white;
  Substance substance;                      /// Substance — the variant's match key (was the name-class)
  Source source;                            /// Source — which tile/feature produced this variant
  float food = 0.0f;                        /// edibility (from the producing brush); 0 => inedible
  float traverse = 0.0f;                    /// walk cost; 0 => impassable (liquids)
  bool build = false;                       /// may be placed/built with
  int maxStack = 1;                         /// stack size when carried as a raw item
}

/** A crafted item template (shape) parsed from items.txt into itemTemplateTable. */
struct ItemTemplateT {
  string name = "None";
  string mesh = "Cube";    /// shape geometry (tinted/textured by material at use time)
  string tex3D = "";       /// world texture (model atlas); empty => use `tex`
  string tex  = "";        /// template skin; empty => fall back to the material's texture
  string texFilled = "";   /// skin when the container holds contents (amount > 0); empty => use `tex`
  float scale = 1.0f;      /// render scale of the crafted item
  float offsetY = 0.0f;    /// vertical render offset (model units) for model-backed items
  Substance[] accepts;     /// Substance the material may belong to; empty => any
  Substance[] holds;       /// Substance the contents may belong to; empty => not a container
  uint capacity = 0;       /// max units of contents (0 => not a container; a cup = 1)
  int maxStack = 1;        /// stack size of the crafted item
  float food = 0.0f;       /// nutrition restored when eaten (0 => not edible)
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

