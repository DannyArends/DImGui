/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry;
import search : performSearch, atGoal, stepThroughPath;
import world : setTile;
import tileatlas : tileData;

int[3][] miningQueue;  // global

class Dwarf : Cylinder {
  string dwarfName;
  int[3] tilePos = [0, 0, 0];  /// Current tile position in world coordinates
  int[3] targetTile = [int.min, 0, 0];  // claimed job
  float[3][] path;                        // world-space path
  float miningProgress = 0.0f;
}

bool isTileOccupied(ref App app, int[3] tile) {
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o; if(d !is null && d.tilePos == tile) return true;
  }
  return false;
}

string randomDwarfName() {
  string[] prefixes = ["Urist", "Iden", "Meng", "Reg", "Doren", "Ast", "Nil", "Erib", "Thob", "Cog"];
  string[] suffixes = ["ral", "dor", "zan", "kel", "tok", "mis", "bur", "ith", "gar", "lon"];
  return prefixes[uniform(0, prefixes.length)] ~ suffixes[uniform(0, suffixes.length)];
}

int surfaceY(ref App app, int x, int z) {
  for(int y = app.world.chunkHeight-1; y > 0; y--) {
    int[3] tile = [x, y, z];
    auto coord = app.world.chunkCoord(tile);
    TileType tt = (coord in app.world.chunks) ?
      app.world.chunks[coord].tileTypes[app.world.tileIndex(app.world.localCoord(tile))] :
      app.world.getTile(tile);
    if(tt != TileType.None) return y;
  }
  return 0;
}

int[3] findFreeSurfaceTile(ref App app, int startX = 0, int startZ = 0) {
  foreach(radius; 0..app.world.chunkSize) {
    for(int x = -radius; x <= radius; x++) {
      for(int z = -radius; z <= radius; z++) {
        int[3] tile = [startX + x, app.world.chunkHeight-1, startZ + z];
        while(tile[1] > 0) {
          auto coord = app.world.chunkCoord(tile);
          TileType tt = (coord in app.world.chunks) ? 
            app.world.chunks[coord].tileTypes[app.world.tileIndex(app.world.localCoord(tile))] :
            app.world.getTile(tile);
          if(tt != TileType.None) break;
          tile[1]--;
        }
        if(tile[1] > 0 && !app.isTileOccupied(tile)) return tile;
      }
    }
  }
  return [int.min, 0, 0];
}

TileType getTileAt(ref App app, int[3] tile) {
  auto coord = app.world.chunkCoord(tile);
  return (coord in app.world.chunks) ?
    app.world.chunks[coord].tileTypes[app.world.tileIndex(app.world.localCoord(tile))] :
    app.world.getTile(tile);
}

void dwarfTick(ref App app, ref Geometry obj) {
  auto d = cast(Dwarf)obj;
  if(d is null) return;

  SDL_Log("Dwarf %s @ tile[%d,%d,%d] target[%d,%d,%d] path:%d mining:%.2f",
    toStringz(d.dwarfName),
    d.tilePos[0], d.tilePos[1], d.tilePos[2],
    d.targetTile[0], d.targetTile[1], d.targetTile[2],
    d.path.length, d.miningProgress);

  // Claim a job
if(d.targetTile[0] == int.min && miningQueue.length > 0) {
  d.targetTile = miningQueue[0];
  miningQueue = miningQueue[1..$];

  // Find a traversable neighbour to stand on while mining
  int[3][4] neighbours = [[d.targetTile[0]+1, d.targetTile[1], d.targetTile[2]],
                          [d.targetTile[0]-1, d.targetTile[1], d.targetTile[2]],
                          [d.targetTile[0],   d.targetTile[1], d.targetTile[2]+1],
                          [d.targetTile[0],   d.targetTile[1], d.targetTile[2]-1]];
  int[3] standTile = [int.min, 0, 0];
  foreach(n; neighbours) {
    if(tileData[app.getTileAt(n)].traversable) { standTile = n; break; }
  }
  if(standTile[0] == int.min) {
    miningQueue ~= d.targetTile;  // no access, requeue
    d.targetTile = [int.min, 0, 0];
    return;
  }

  auto ws = app.world.worldPos(d.tilePos);
  float[3] start = [ws[0], ws[1] + app.world.yOffset, ws[2]];
  auto wg = app.world.worldPos([standTile[0], standTile[1] + 1, standTile[2]]);
  float[3] goal = [wg[0], wg[1] + app.world.yOffset, wg[2]];
    SDL_Log("Dwarf %s pathfinding from [%.1f,%.1f,%.1f] to [%.1f,%.1f,%.1f]",
      toStringz(d.dwarfName), start[0], start[1], start[2], goal[0], goal[1], goal[2]);
    auto result = performSearch!(WorldData, PathNode)(start, goal, app.world.data);
    SDL_Log("Search: %s steps:%d", toStringz(format("%s", result.state)), result.steps);
    d.path = [];
    if(result.state == SearchState.SUCCEEDED || result.state == SearchState.SEARCHING)
      while(!result.atGoal()) d.path ~= result.stepThroughPath(false);
  }

  // Follow path
  if(d.path.length > 0) {
    auto next = d.path[0];
    d.path = d.path[1..$];
    int nx = cast(int)(next[0] / app.world.tileSize);
    int ny = cast(int)((next[1] - app.world.yOffset) / app.world.tileHeight);
    int nz = cast(int)(next[2] / app.world.tileSize);
    d.tilePos = [nx, ny, nz];
    auto wp = app.world.worldPos([nx, ny + 1, nz]);
    d.position([wp[0], wp[1] + app.world.yOffset - 0.5f, wp[2]]);
    auto tileBelow = app.world.getTileAt([d.tilePos[0], d.tilePos[1]-1, d.tilePos[2]]);
    auto tileAt    = app.world.getTileAt(d.tilePos);
    auto tileAbove = app.world.getTileAt([d.tilePos[0], d.tilePos[1]+1, d.tilePos[2]]);
    SDL_Log("Dwarf %s moved to tile[%d,%d,%d] worldpos[%.1f,%.1f,%.1f] below:%s at:%s above:%s",
      toStringz(d.dwarfName), d.tilePos[0], d.tilePos[1], d.tilePos[2],
      next[0], next[1], next[2],
      toStringz(format("%s", tileBelow)),
      toStringz(format("%s", tileAt)),
      toStringz(format("%s", tileAbove)));
  }

  // Mine target
    auto dx = abs(d.tilePos[0] - d.targetTile[0]);
    auto dz = abs(d.tilePos[2] - d.targetTile[2]);
    if(d.targetTile[0] != int.min && d.path.length == 0 && dx + dz <= 1) {
    d.miningProgress += 0.25f;
    SDL_Log("Dwarf %s mining [%d,%d,%d] %.0f%%", toStringz(d.dwarfName),
      d.targetTile[0], d.targetTile[1], d.targetTile[2], d.miningProgress * 100);
    if(d.miningProgress >= 1.0f) {
      app.setTile(d.targetTile);
      d.targetTile = [int.min, 0, 0];
      d.miningProgress = 0.0f;
    }
  }
}

void spawnDwarf(ref App app, string name) {
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  Dwarf dwarf = new Dwarf();
  dwarf.dwarfName = name;
  dwarf.tilePos = tile;
  auto wp = app.world.worldPos([tile[0], tile[1] + 1, tile[2]]);
  dwarf.position([wp[0], wp[1] + app.world.yOffset - 0.5, wp[2]]);
  dwarf.setColor([uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), 1.0f]);
  dwarf.onTick = &dwarfTick;
  app.objects ~= dwarf;
}

