/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import vector : x, y, z, vMul, vAdd;
/** Reserved lattice coordinates (never valid cells) */
enum int[3] noTile     = [int.min, 0, 0];
enum int[3] builtTile  = [int.max, 0, 0];
enum int[3] storedTile = [int.min + 1, 0, int.min + 1];

/** The six axis-aligned neighbour offsets (±X, ±Y, ±Z) */
static immutable int[3][6] FACE_OFFSETS = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
static immutable float[3][6] FACE_TANGENT = [[0,0,1],[0,0,-1],[1,0,0],[1,0,0],[1,0,0],[-1,0,0]];     // in-plane U axis per faces

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

/** One sparse cell change: which chunk, which linear tile index, and the value there */
struct Diff(T) { int[3] coord; uint idx; T value; }

/** Flatten a chunked sparse map (chunk-coord to tile-index to value) into a blittable Diff!V array */
Diff!T[] flatten(T)(const T[uint][int[3]] map) { 
  Diff!T[] flat;
  foreach(coord, idxMap; map) foreach(idx, value; idxMap) flat ~= Diff!T(coord, idx, value);
  return flat;
}

/** Rebuild a chunked sparse map from a Diff!V array (replaces any existing contents) */
LatticeMap!(T[uint]) unflatten(T)(const Diff!T[] flat) {
  LatticeMap!(T[uint]) map;
  foreach(d; flat) map[d.coord][d.idx] = d.value;
  return(map);
}

/** Chunk-local linear index to local (x, y, z) coordinate within the chunk */
@nogc pure int[3] tileCoord(T)(const T l, int i) nothrow { 
  return [i % l.chunkSize, (i / l.chunkSize) % l.chunkHeight, i / (l.chunkSize * l.chunkHeight)];
}

/** World tile coordinate to world-space float position (plus optional extra Y offset) */
@nogc pure float[3] tileToWorld(T)(const T l, const int[3] tile, float yOff = 0.0f) nothrow {
  return [tile.x * l.tileSize, tile.y * l.tileHeight + l.yOffset + yOff, tile.z * l.tileSize];
}

/** World-space float position to the world tile coordinate containing it */
@nogc pure int[3] worldToTile(T)(const T l, float[3] pos, float yOff = 0.0f) nothrow {
  return [cast(int)(pos.x / l.tileSize), cast(int)((pos.y - l.yOffset - yOff) / l.tileHeight), cast(int)(pos.z / l.tileSize)];
}

/** Chunk-local coordinate to linear per-chunk tile index */
@nogc pure int tileIndex(T)(const T l, const int[3] local) nothrow { 
  return(local.z * l.chunkHeight * l.chunkSize + local.y * l.chunkSize + local.x);
}

/** World tile coordinate to linear per-chunk tile index */
@nogc pure int tileIdx(T)(const T l, const int[3] tile) nothrow { return l.tileIndex(l.localCoord(tile)); }

/** The tile directly below (−Y) */
@nogc pure int[3] tileBelow(const int[3] tile) nothrow { return [tile.x, tile.y - 1, tile.z]; }

/** The tile directly above (+Y) */
@nogc pure int[3] tileAbove(const int[3] tile) nothrow { return [tile.x, tile.y + 1, tile.z]; }

/** True if a chunk-local tile sits on the x or z edge of the chunk (needs cross-chunk neighbour lookup) */
@nogc pure bool onChunkBoundary(T)(const T l, const int[3] lc) nothrow { return lc.x == 0 || lc.x == l.chunkSize-1 || lc.z == 0 || lc.z == l.chunkSize-1; }

/** Terrain surface height in tiles for normalised noise height 'h0' within a chunk of 'chunkHeight' */
@nogc pure int surfaceLevel(float h0, int chunkHeight) nothrow { return cast(int)(h0 * sqrt(h0) * (chunkHeight - 1)); }

/** Floor division (rounds toward -inf) — negative-safe chunk coordinates. */
@nogc pure int iDiv(int a, int b) nothrow { return((a >= 0) ? a/b : -((-a + b - 1)/b)); }

/** World tile coordinate to the coordinate of the chunk containing it (Y forced to 0; chunks are full-height columns) */
@nogc pure int[3] chunkCoord(T)(const T l, const int[3] tile) nothrow {
  return [iDiv(tile.x, l.chunkSize), 0, iDiv(tile.z, l.chunkSize)];
}

/** Convert a world tile coordinate to its local coordinate within its chunk */
@nogc pure int[3] localCoord(T)(const T l, const int[3] tile) nothrow {
  auto coord = l.chunkCoord(tile);
  return [tile.x - coord.x * l.chunkSize, tile.y, tile.z - coord.z * l.chunkSize];
}

/** Convert a chunk coordinate and local tile coordinate to a world tile coordinate */
@nogc pure int[3] worldCoord(T)(const T l, const int[3] coord, const int[3] local) nothrow {
  return coord.vMul([l.chunkSize, l.chunkHeight, l.chunkSize]).vAdd(local);
}

/** The six axis-aligned neighbours of a lattice coordinate (±X, ±Y, ±Z). */
@nogc pure int[3][6] tileNeighbours(const int[3] wc) nothrow {
  int[3][6] r;
  foreach(f; 0 .. 6) r[f] = [wc[0]+FACE_OFFSETS[f][0], wc[1]+FACE_OFFSETS[f][1], wc[2]+FACE_OFFSETS[f][2]];
  return r;
}
