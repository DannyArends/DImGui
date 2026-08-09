/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 * All CTFE raw template structs. Engine-only (imports lsystem/color, never game/raws) so raws' CTFE cannot cycle.
 */

import phobos;

import color : Colors;
import ctfe : composedEnum, enumFromTag, EnumRule;
import lsystem : LSystemBrushT, Rule;

enum WorkshopUse : ubyte { None, Required, Preferred }

mixin(enumFromTag(import("data/raws/items.txt"), "ITEM", "ItemTemplate", "None"));
mixin(enumFromTag(import("data/raws/substance.txt"), "SUBSTANCE", "Substance", "None"));

mixin(composedEnum("Source", "None",
  [EnumRule("TILE"), EnumRule("FEATURE")],
  import("data/raws/tiles.txt"), import("data/raws/features.txt")));

// ResourceType = every tile, then <Feature><Substance> per brush (grouped by FEATURE, brush field 3)
mixin(composedEnum("ResourceType", "",
  [EnumRule("TILE"), EnumRule("BRUSH", "FEATURE", 3)],
  import("data/raws/tiles.txt"), import("data/raws/features.txt")));

enum size_t RESOURCE_COUNT = ResourceType.max + 1;   /// Number of ResourceType members (variants)
alias SpawnMask = bool[RESOURCE_COUNT];

/** Per-species entity template: pawn behaviour + an L-system body baked into an OpenAsset. */
struct EntityT {
  string name;                                   /// Species name, e.g. "Dwarf"
  float moveSpeed = 2.0f;                        /// Tiles per second
  float hungerDecay = 0.0f, thirstDecay = 0.0f;  /// Need growth per tick
  string diet;                                   /// Substance/type eaten (empty = none)
  float scale = 1.0f, scaleVariance = 0.0f;      /// Instance scale + per-spawn variance
  float offsetY = 0.0f;                          /// Vertical render offset to seat on the tile
  float facing = 0.0f;                           /// Yaw offset correcting the model's forward axis
  string axiom = "B";                            /// L-system start symbol(s)
  Rule[] rules;                                  /// L-system production rules (empty = axiom as-is)
  LSystemBrushT[] brushes;                        /// Symbol -> mesh brushes (entities ignore the material fields)
  float lsystemYaw = 25.0f, lsystemPitch = 25.0f, lsystemRoll = 25.0f;
  float lsystemGap = 0.2f;                       /// f translation step (no draw)
}

/** Data-driven animal species, parsed from data/raws/animals.txt into animalTable. */
struct AnimalT {
  string name;                                  /// Species name
  string mesh = "Torus";                        /// Instance mesh (primitive for now)
  ubyte[] spawnOn;                              /// cast(ubyte)ResourceType tiles this animal spawns on
  float noiseThreshold = 0.92f;                 /// Hash-noise spawn gate (higher = rarer)
  uint hashSeed1, hashSeed2;                    /// Per-species spawn hash seeds
  uint hashMod, hashRem;                        /// Optional hash bucketing (0 = unused)
  float moveSpeed = 2.0f;                       /// Tiles per second
  float hungerDecay = 0.00040f;                 /// Hunger need increase per tick
  float thirstDecay = 0.00060f;                 /// Thirst need increase per tick
  string diet = "Berry";                        /// Resource (class or type) this animal eats
  float scale = 0.5f, scaleVariance = 0.1f;     /// Instance scale + per-spawn variance
  float offsetY = 0.0f;                          /// Vertical render offset (world units) to sit model on the tile
  float facing = 0.0f;                          /// Yaw offset (degrees) correcting the model's forward axis
}

/** Data-driven terrain feature (tree/bush/cactus): spawn rules + an L-system body. */
struct FeatureT {
  string name;
  string[] spawnOn;
  float noiseThreshold = 0.65f;
  uint hashSeed1, hashSeed2;
  uint hashMod, hashRem;
  uint heightMin = 1, heightMax = 1;
  float tilePenalty = 0.0f;
  float progressRate = 0.25f;
  string interaction;
  string sound;
  float lsystemYaw = 25.0f, lsystemPitch = 25.0f, lsystemRoll = 25.0f;
  LSystemBrushT[] brushes;
  string axiom = "X";
  Rule[] rules;
}

/** A tile/feature variant = substance @ source; the row backing each ResourceType member. */
struct ResourceT {
  string name = "None", meshName = "Blocks", tex3D = "", tex2D = "";
  float scale = 1.0f;
  float offsetY = 0.0f;                     /// vertical render offset (world units) for model-backed drops
  Colors color = Colors.white;
  ubyte substance = 0;                      /// cast(ubyte)Substance — the variant's match key (was the name-class)
  ubyte source = 0;                         /// cast(ubyte)Source — which tile/feature produced this variant
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
  ubyte[] accepts;         /// Substance the material may belong to; empty => any
  ubyte[] holds;           /// Substance the contents may belong to; empty => not a container
  uint capacity = 0;       /// max units of contents (0 => not a container; a cup = 1)
  int maxStack = 1;        /// stack size of the crafted item
  float food = 0.0f;       /// nutrition restored when eaten (0 => not edible)
}

struct Ingredient { ubyte cls; ubyte item = 0; uint count = 1; }

/** One output line: a raw material (shape == None, `type` names the ResourceType) OR a crafted item
 *  (shape != None) whose material is inherited from the consumed input of class `materialFrom`. */
struct Product { ubyte shape = 0; ubyte type = 0; ubyte materialFrom = 0; float chance = 1.0f; uint count = 1; }

struct Reaction {
  string name, verb, skill;
  float progressRate = 1.0f;
  WorkshopUse workshop;
  Ingredient[] inputs;
  Product[] outputs;
}

/** One terrain height band: an upper threshold and the resources eligible at that height. */
struct HeightBand { float threshold; ubyte[] results; }
