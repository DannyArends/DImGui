/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import noise : noise2D;
import pathfinding : invalidatePaths;
import vector : x,y,z;

struct TileDiff {
  int[3] coord;
  uint idx;
  uint type;
}

enum int[3] noTile = [int.min, 0, 0];
enum int[3] builtTile = [int.max, 0, 0];
enum int[3] storedTile = [int.min + 1, 0, int.min + 1];

static immutable int[3][6] FACE_OFFSETS = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];

/** Is the Tile occupied ?  */
@nogc pure bool isTileOccupied(const GameApp app, const int[3] tile) nothrow {
  if(app.world.dwarves !is null) { foreach(ref d; app.world.dwarves) { if(d.tile == tile) return true; } }
  return false;
}

/** True if a chunk-local tile sits on the x or z edge of the chunk (needs cross-chunk neighbour lookup) */
@nogc pure bool onChunkBoundary(T)(T wd, int[3] lc) nothrow {
  return lc[0] == 0 || lc[0] == wd.chunkSize-1 || lc[2] == 0 || lc[2] == wd.chunkSize-1;
}

/** Water level (0..WATER_MAX) at a world tile; 0 if chunk not loaded or out of range */
@nogc int getWater(const World world, int[3] tile) nothrow {
  if(tile[1] < 0 || tile[1] >= world.chunkHeight) return 0;
  auto p = world.chunkCoord(tile) in world.chunks;
  return p is null ? 0 : (*p).waterLevel[world.tileIdx(tile)];
}

/** Wake a cell and its 6 neighbours so the sim re-evaluates them next tick. */
void activate(ref GameApp app, int[3] tile) {
  if(tile[1] < 0 || tile[1] >= app.world.chunkHeight) return;
  auto p = app.world.chunkCoord(tile) in app.world.chunks;
  if(p is null) return;
  auto ch = *p;
  int idx = app.world.tileIdx(tile);
  auto lc = app.world.tileCoord(idx);
  if(ch.waterLevel[idx] > 0) ch.active ~= idx;
  foreach(d; FACE_OFFSETS) {
    int[3] nc; int nidx;
    if(!app.world.neighbourAt(ch.coord, lc, d, nc, nidx)) continue;
    Chunk nch = (nc == ch.coord) ? ch : app.world.chunks[nc];   // reuse in-chunk -> no hash
    if(nch.waterLevel[nidx] > 0) nch.active ~= nidx;
  }
}

/** Set water level (0 .. WATER_MAX) at a world tile; marks the chunk dirty for re-mesh */
void setWater(ref GameApp app, int[3] tile, ubyte level, bool wake = true) {
  int[3] coord = app.world.chunkCoord(tile);
  if(tile[1] < 0 || tile[1] >= app.world.chunkHeight) return;
  if(coord !in app.world.chunks) return;
  int idx = app.world.tileIdx(tile);
  auto chunk = app.world.chunks[coord];
  if(level == 0) chunk.active.remove(idx);
  ubyte old = chunk.waterLevel[idx];
  if(old == level) return;
  if(old == 0 && level > 0){
    chunk.wetCells ~= idx;
  }else if(old > 0 && level == 0){ chunk.wetCells.remove(idx); }
  chunk.waterLevel[idx] = cast(ubyte)level;
  chunk.waterDirty = true;
  if(wake){ app.activate(tile); }
}

/** True if all 6 neighbours of interior tile i are solid (caller guarantees i is not on a boundary) */
@nogc pure bool isBuried(T)(T wd, const ResourceType[] types, int i, int[3] lc) nothrow {
  if (lc[1] == 0 || lc[1] >= wd.chunkHeight-1) return false;
  int dy = wd.chunkSize, dz = wd.chunkHeight * wd.chunkSize;
  return types[i-1]  != ResourceType.None && types[i+1]  != ResourceType.None &&
         types[i-dy] != ResourceType.None && types[i+dy] != ResourceType.None &&
         types[i-dz] != ResourceType.None && types[i+dz] != ResourceType.None;
}

/** Set a tile type in a chunk and mark the chunk dirty for rebuild */
void setTile(ref GameApp app, int[3] tile, ResourceType newType = ResourceType.None) {
  if(app.world.getTile(tile) == ResourceType.Lava) return;  // cannot remove lava
  if(app.verbose) SDL_Log(cstr("setTile: %s", tile));

  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in app.world.chunks) return;
  if (coord[1] < 0 || coord[1] >= app.world.chunkHeight) return;
  int idx = app.world.tileIdx(tile);

  app.world.chunks[coord].tileTypes[idx] = newType;
  app.world.data.diffs[coord][idx] = newType;
  app.world.chunks[coord].dirty = true;

  // Mark neighbouring chunks dirty if tile is on a chunk boundary
  foreach (n; app.world.tileNeighbours(tile)) {
    int[3] nc = app.world.chunkCoord(n);
    if (nc != coord && nc in app.world.chunks) app.world.chunks[nc].dirty = true;
  }
  app.world.pendingPaths = [];
  app.invalidatePaths(tile);
  app.shadows.staticDirty[] = true;
  if(newType == ResourceType.None) app.activate(tile);   // mined out: wake neighbouring water to flow in
}

@nogc pure int[3] tileBelow(int[3] tile) nothrow { return [tile[0], tile[1] - 1, tile[2]]; }
@nogc pure int[3] tileAbove(int[3] tile) nothrow { return [tile[0], tile[1] + 1, tile[2]]; }

/** Resolve a neighbour of local (lx,ly,lz) in `chunk` by offset (dx,dy,dz) to (out chunk, out idx).
    In-chunk: pure integer offset, no hash. Boundary: one chunk-pointer hop. False if out of loaded world. */
@nogc bool neighbourAt(const World world, const int[3] coord, int[3] lc, int[3] offset, out int[3] nCoord, out int nidx) nothrow {
  int S = world.chunkSize, Hh = world.chunkHeight;
  int ny = lc.y + offset.y;
  if(ny < 0 || ny >= Hh) return false;
  int nx = lc.x + offset.x, nz = lc.z + offset.z;
  if(nx >= 0 && nx < S && nz >= 0 && nz < S) { nCoord = coord; nidx = nz*Hh*S + ny*S + nx; return true; }
  int cdx = nx < 0 ? -1 : (nx >= S ? 1 : 0);
  int cdz = nz < 0 ? -1 : (nz >= S ? 1 : 0);
  nCoord = [coord[0]+cdx, 0, coord[2]+cdz];
  if(nCoord !in world.chunks) return false;
  nidx = ((nz+S)%S)*Hh*S + ny*S + ((nx+S)%S);
  return true;
}

@nogc pure int surfaceLevel(float h0, int chunkHeight) nothrow { return cast(int)(h0 * sqrt(h0) * (chunkHeight - 1)); }

/** Determine the tile type at a world coordinate from noise, no chunk data required */
@nogc pure ResourceType getTile(T)(T wd, const int[3] wc) nothrow {
  float h0 = noise2D(wc.x, wc.z, wd.seed[0]);
  int surface = surfaceLevel(h0, wd.chunkHeight);
  if (wc.y > surface) return ResourceType.None;
  if (wc.y == 0) return ResourceType.Lava;
  if (wc.y < surface) return ResourceType.Stone01;
  return heightToResource(h0, noise2D(wc.x, wc.z, wd.seed[1]));
}

@nogc pure int[3] tileCoord(T)(T wd, int i) nothrow { 
  return [i % wd.chunkSize, (i / wd.chunkSize) % wd.chunkHeight, i / (wd.chunkSize * wd.chunkHeight)];
}

@nogc pure float[3] tileToWorld(T)(T wd, int[3] tile, float yOff = 0.0f) nothrow {
  return [tile.x * wd.tileSize, tile.y * wd.tileHeight + wd.yOffset + yOff, tile.z * wd.tileSize];
}

@nogc pure int[3] worldToTile(T)(T wd, float[3] pos, float yOff = 0.0f) nothrow {
  return [cast(int)(pos[0] / wd.tileSize), cast(int)((pos[1] - wd.yOffset - yOff) / wd.tileHeight), cast(int)(pos[2] / wd.tileSize)];
}

@nogc pure int tileIndex(T)(T wd, int[3] local) nothrow { return(local.z * wd.chunkHeight * wd.chunkSize + local.y * wd.chunkSize + local.x); }

@nogc pure int tileIdx(T)(T wd, int[3] tile) nothrow { return wd.tileIndex(wd.localCoord(tile)); }

@nogc pure int surfaceAt(T)(T wd, int x, int y, int z) nothrow {
  int ns = surfaceLevel(noise2D(x, z, wd.seed[0]), wd.chunkHeight);
  if((wd.chunkCoord([x, y, z]) in wd.diffs) is null) return y < ns ? y : ns;
  while(y > 0 && wd.getTileAt([x, y, z]) == ResourceType.None){ y--; }
  return y;
}

@nogc pure bool isPassable(T)(T wd, int[3] wc) nothrow {
  if(wc[1] <= 0 || wc[1] >= wd.chunkHeight){ return(false); }
  return wd.getTileAt(wc) == ResourceType.None;
}

/** True if the world tile is solid (computed from noise); below-world counts as solid, above-world as air */
@nogc pure bool isSolid(T)(T wd, const int[3] wc) nothrow {
  if (wc[1] < 0) return true; // below world = solid (cull face)
  if (wc[1] >= wd.chunkHeight) return false; // above world = air (expose face)
  return(wd.getTileAt(wc) != ResourceType.None);
}

@nogc pure bool isStandable(T)(T wd, const int[3] tile) nothrow {
  return(wd.isPassable(tile) && wd.getTileAt(tileBelow(tile)) != ResourceType.None && resourceData(wd.getTileAt(tileBelow(tile))).traversable);
}

@nogc pure bool hasStandableNeighbour(T)(T wd, int[3] tile) nothrow {
  auto n = wd.tileNeighbours(tile);
  foreach(i; [0,1,4,5]) { if(wd.isStandable(n[i])) return true; }
  return false;
}

pure PathNode[] getSuccessors(T)(T wd, PathNode parent) {
  PathNode[] successors;
  auto pt = wd.worldToTile(parent.position);
  foreach(dir; [[1,0],[-1,0],[0,1],[0,-1]]) {
    int nx = pt[0] + dir[0], nz = pt[2] + dir[1];
    foreach(dy; [-1, 0, 1]) {
      int ny = (pt[1] - 1) + dy;
      auto tt = wd.getTileAt([nx, ny, nz]);
      int[3] standTile = [nx, ny+1, nz];
      if(tt != ResourceType.None && resourceData(tt).traversable && wd.isPassable(standTile)) {
        float modifier = wd.tilePenalties.get(standTile, 0.0f);
        successors ~= PathNode(position: [nx*wd.tileSize, (ny+1)*wd.tileHeight+wd.yOffset, nz*wd.tileSize], cost: resourceData(tt).cost + modifier);
        break;
      }
    }
  }
  return successors;
}

/** Tile type at a world coordinate. For loaded chunks reads the resolved grid (diffs baked in,
 *  kept in sync by setTile); otherwise falls back to the diff overlay, then to raw noise. */
@nogc pure ResourceType getTileAt(T)(T wd, int[3] tile) nothrow {
  int[3] coord = wd.chunkCoord(tile);
  int idx = wd.tileIdx(tile);
  static if(is(typeof(wd.chunks))) {  // Fast path: World keeps a per-voxel grid per loaded chunk
    if(auto chunk = coord in wd.chunks) {
      if(*chunk !is null && idx >= 0 && idx < (*chunk).tileTypes.length) { return((*chunk).tileTypes[idx]); }
    }
  }
  // Fallback (worker snapshot / unloaded chunk)
  if(auto diff = coord in wd.diffs) { if(auto type = cast(uint)idx in *diff) { return(*type); } }
  return wd.getTile(tile);  // If none, derive it from noise
}

