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

/** Is the Tile occupied ?  */
@nogc pure bool isTileOccupied(const GameApp app, const int[3] tile) nothrow {
  if(app.world.dwarves !is null) { foreach(ref d; app.world.dwarves) { if(d.tile == tile) return true; } }
  return false;
}

/** True if a chunk-local tile sits on the x or z edge of the chunk (needs cross-chunk neighbour lookup) */
@nogc pure bool onChunkBoundary(T)(T wd, int[3] lc) nothrow {
  return lc[0] == 0 || lc[0] == wd.chunkSize-1 || lc[2] == 0 || lc[2] == wd.chunkSize-1;
}

/** Water level (0..6) at a world tile; 0 if chunk not loaded or out of range */
@nogc int getWater(ref GameApp app, int[3] tile) nothrow {
  int[3] coord = app.world.chunkCoord(tile);
  if(tile[1] < 0 || tile[1] >= app.world.chunkHeight) return 0;
  if(coord !in app.world.chunks) return 0;
  return app.world.chunks[coord].waterLevel[app.world.tileIdx(tile)];
}

/** Set water level (0..6) at a world tile; marks the chunk dirty for re-mesh */
void setWater(ref GameApp app, int[3] tile, ubyte level) {
  int[3] coord = app.world.chunkCoord(tile);
  if(tile[1] < 0 || tile[1] >= app.world.chunkHeight) return;
  if(coord !in app.world.chunks) return;
  int idx = app.world.tileIdx(tile);
  if(app.world.chunks[coord].waterLevel[idx] == level) return;   // no change, no dirty
  app.world.chunks[coord].waterLevel[idx] = level;
  app.world.chunks[coord].dirty = true;
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
}

@nogc pure int[3] tileBelow(int[3] tile) nothrow { return [tile[0], tile[1] - 1, tile[2]]; }
@nogc pure int[3] tileAbove(int[3] tile) nothrow { return [tile[0], tile[1] + 1, tile[2]]; }

/** Determine the tile type at a world coordinate from noise, no chunk data required */
@nogc pure ResourceType getTile(T)(T wd, const int[3] wc) nothrow {
  float h0 = noise2D(wc.x, wc.z, wd.seed[0]);
  int surface = cast(int)(h0 * sqrt(h0) * (wd.chunkHeight - 1));
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
@nogc pure int surfaceAt(T)(T wd, int x, int y, int z) nothrow { while(y > 0 && wd.getTileAt([x, y, z]) == ResourceType.None){ y--; } return y; }
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

@nogc pure ResourceType getTileAt(T)(T wd, int[3] tile) nothrow {
  auto coord = wd.chunkCoord(tile);
  auto idx = wd.tileIdx(tile);
  if(auto cm = coord in wd.diffs) if(auto t = cast(uint)idx in *cm) return *t;
  return wd.getTile(tile);
}

