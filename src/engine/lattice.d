/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

/** Regular 3D lattice of (possibly non-cubic) cells */
struct Lattice {
  float tileSize = 1.0f;      /// Size (X & Z) of a tile
  float tileHeight = 1.0f;    /// Y-spacing between tiles
  int chunkSize = 64;         /// Number of tiles (X & Z) in a chunk
  int chunkHeight = 64;       /// Number of tiles (Y) in a chunk
  float yOffset = 0.0f;       /// Global world Y-offset
}

/** A value indexed by an integer 3D lattice coordinate (tile- or chunk-space key) */
alias LatticeMap(T) = T[int[3]];

/** Reserved lattice coordinates (never valid cells) */
enum int[3] noTile     = [int.min, 0, 0];
enum int[3] builtTile  = [int.max, 0, 0];
enum int[3] storedTile = [int.min + 1, 0, int.min + 1];

/** The six axis-aligned neighbour offsets (±X, ±Y, ±Z) */
static immutable int[3][6] FACE_OFFSETS = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];