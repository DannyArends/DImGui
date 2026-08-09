/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 * All CTFE raw template structs. Engine-only (imports lsystem/color, never game/raws) so raws' CTFE cannot cycle.
 */

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