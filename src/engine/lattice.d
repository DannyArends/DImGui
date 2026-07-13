/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import vector : x, y, z, vMul, vAdd;

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

@nogc pure int[3] tileCoord(T)(const T l, int i) nothrow { return [i % l.chunkSize, (i / l.chunkSize) % l.chunkHeight, i / (l.chunkSize * l.chunkHeight)]; }

@nogc pure float[3] tileToWorld(T)(const T l, int[3] tile, float yOff = 0.0f) nothrow {
  return [tile.x * l.tileSize, tile.y * l.tileHeight + l.yOffset + yOff, tile.z * l.tileSize];
}

@nogc pure int[3] worldToTile(T)(const T l, float[3] pos, float yOff = 0.0f) nothrow {
  return [cast(int)(pos[0] / l.tileSize), cast(int)((pos[1] - l.yOffset - yOff) / l.tileHeight), cast(int)(pos[2] / l.tileSize)];
}

@nogc pure int tileIndex(T)(const T l, int[3] local) nothrow { return(local.z * l.chunkHeight * l.chunkSize + local.y * l.chunkSize + local.x); }

@nogc pure int tileIdx(T)(const T l, int[3] tile) nothrow { return l.tileIndex(l.localCoord(tile)); }

@nogc pure int[3] tileBelow(const int[3] tile) nothrow { return [tile[0], tile[1] - 1, tile[2]]; }
@nogc pure int[3] tileAbove(const int[3] tile) nothrow { return [tile[0], tile[1] + 1, tile[2]]; }

/** True if a chunk-local tile sits on the x or z edge of the chunk (needs cross-chunk neighbour lookup) */
@nogc pure bool onChunkBoundary(T)(const T l, int[3] lc) nothrow { return lc[0] == 0 || lc[0] == l.chunkSize-1 || lc[2] == 0 || lc[2] == l.chunkSize-1; }

@nogc pure int surfaceLevel(float h0, int chunkHeight) nothrow { return cast(int)(h0 * sqrt(h0) * (chunkHeight - 1)); }

/** Floor division (rounds toward -inf) — negative-safe chunk coordinates. */
@nogc pure int iDiv(int a, int b) nothrow { return((a >= 0) ? a/b : -((-a + b - 1)/b)); }

/** Convert a chunk coordinate and local tile coordinate to a world tile coordinate */
@nogc pure int[3] chunkCoord(T)(const T l, const int[3] tile) nothrow {
  return [iDiv(tile[0], l.chunkSize), 0, iDiv(tile[2], l.chunkSize)];
}

/** Convert a world tile coordinate to its local coordinate within its chunk */
@nogc pure int[3] localCoord(T)(const T l, const int[3] tile) nothrow {
  auto coord = l.chunkCoord(tile);
  return [tile.x - coord.x * l.chunkSize, tile.y, tile.z - coord.z * l.chunkSize];
}

/** Convert a chunk coordinate and local tile coordinate to a world tile coordinate */
@nogc pure int[3] worldCoord(T)(const T l, int[3] coord, int[3] local) nothrow {
  return coord.vMul([l.chunkSize, l.chunkHeight, l.chunkSize]).vAdd(local);
}

/** The six axis-aligned neighbours of a lattice coordinate (±X, ±Y, ±Z). */
@nogc pure int[3][6] tileNeighbours(const int[3] wc) nothrow {
  int[3][6] r;
  foreach(f; 0 .. 6) r[f] = [wc[0]+FACE_OFFSETS[f][0], wc[1]+FACE_OFFSETS[f][1], wc[2]+FACE_OFFSETS[f][2]];
  return r;
}
