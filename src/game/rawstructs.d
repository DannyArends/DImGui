/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 * All CTFE raw template structs. Engine-only (imports lsystem/color, never game/raws) so raws' CTFE cannot cycle.
 */

import color : Colors;
import lsystem : LSystemBrushT, Rule;

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
