/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;
import geometry;
import search : performSearch, atGoal, stepThroughPath;
import world : setTile;
import vector : euclidean;
import tileatlas : tileData;

int[3][] miningQueue;

class Dwarf : Cylinder {
  string dwarfName;
  int[3] tilePos    = [0, 0, 0];
  int[3] targetTile = [int.min, 0, 0];
  float[3][] path;
  float miningProgress = 0.0f;
}

bool isTileOccupied(ref App app, int[3] tile) {
  foreach(o; app.objects) { auto d = cast(Dwarf)o; if(d !is null && d.tilePos == tile) return true; }
  return false;
}

string randomDwarfName() {
  string[] prefixes = ["Urist", "Iden", "Meng", "Reg", "Doren", "Ast", "Nil", "Erib", "Thob", "Cog"];
  string[] suffixes = ["ral", "dor", "zan", "kel", "tok", "mis", "bur", "ith", "gar", "lon"];
  return prefixes[uniform(0, prefixes.length)] ~ suffixes[uniform(0, suffixes.length)];
}

bool isStandable(World world, int[3] tile) {
  return world.getTileAt(tile) == TileType.None && world.getTileAt([tile[0], tile[1]-1, tile[2]]) != TileType.None;
}

int[3] findFreeSurfaceTile(ref App app, int startX = 0, int startZ = 0) {
  foreach(radius; 0..app.world.chunkSize) {
    for(int x = -radius; x <= radius; x++) {
      for(int z = -radius; z <= radius; z++) {
        int[3] tile = [startX + x, app.world.chunkHeight-1, startZ + z];
        while(tile[1] > 0) {
          TileType tt = app.world.getTileAt(tile);
          if(tt != TileType.None) break;
          tile[1]--;
        }
        if(tile[1] > 0 && !app.isTileOccupied([tile[0], tile[1]+1, tile[2]])) return [tile[0], tile[1]+1, tile[2]];
      }
    }
  }
  return [int.min, 0, 0];
}

/** Find the closest standable neighbour (air tile with solid below) to the dwarf
 */
int[3] findGoalTile(ref App app, Dwarf d) {
  int[3] goalTile = [int.min, 0, 0];
  float bestDist = float.max;
  foreach (n; app.world.tileNeighbours(d.targetTile)[0..2] ~ app.world.tileNeighbours(d.targetTile)[4..6]) {
    if (!app.world.isStandable(n)) continue;
    float dist = abs(n[0]-d.tilePos[0]) + abs(n[2]-d.tilePos[2]);
    if (dist < bestDist) { bestDist = dist; goalTile = n; }
  }
  return goalTile;
}

/// Compute world-space position from tile coords
float[3] tileToWorld(ref App app, int[3] tile) {
  auto wp = app.world.worldPos(tile);
  return [wp[0], wp[1] + app.world.yOffset, wp[2]];
}

/// Claim a job, find goal tile, compute path
bool claimJob(ref App app, Dwarf d) {
  if(miningQueue.length == 0) return false;
  d.targetTile = miningQueue[0];
  miningQueue = miningQueue[1..$];

  auto goalTile = app.findGoalTile(d);
  if (goalTile[0] == int.min) {
    if(app.verbose) SDL_Log(toStringz(format("Dwarf %s no access to %s, discarding", d.dwarfName, d.targetTile)));
    d.targetTile = [int.min, 0, 0];
    return false;
  }

  float[3] start = app.tileToWorld(d.tilePos);
  float[3] goal  = app.tileToWorld(goalTile);
  if(app.verbose) SDL_Log(toStringz(format("Dwarf %s pathfinding from %s to %s", d.dwarfName, start, goal)));

  auto result = performSearch!(World, PathNode)(start, goal, app.world, app.verbose > 0);
  if(app.verbose) SDL_Log("Search: %s steps:%d", toStringz(format("%s", result.state)), result.steps);

  if(result.state == SearchState.FAILED || result.state == SearchState.INVALID) {
    d.targetTile = [int.min, 0, 0];
    return false;
  }
  d.path = [];
  while(!result.atGoal()) d.path ~= result.stepThroughPath(false);
  d.path ~= [result.goal.x, result.goal.y, result.goal.z];
  return true;
}

/// Move dwarf one step along its path
void followPath(ref App app, Dwarf d) {
  auto next = d.path[0];
  d.path = d.path[1..$];
  d.tilePos = app.world.worldToTile(next);
  auto wp = app.tileToWorld(d.tilePos);
  d.position([wp[0], wp[1] - 0.5f, wp[2]]);
  if(app.verbose) SDL_Log(toStringz(format("Dwarf %s moved to tile %s", d.dwarfName, d.tilePos)));
}

/// Mine the target tile if adjacent
void doMining(ref App app, Dwarf d) {
  auto dx = abs(d.tilePos[0] - d.targetTile[0]);
  auto dz = abs(d.tilePos[2] - d.targetTile[2]);
  if(dx + dz == 1 && d.tilePos[1] == d.targetTile[1]) {
    d.miningProgress += 0.25f;
    if(app.verbose) SDL_Log(toStringz(format("Dwarf %s mining %s %.0f%%", d.dwarfName, d.targetTile, d.miningProgress * 100)));
    if(d.miningProgress >= 1.0f) {
      app.setTile(d.targetTile);
      d.targetTile = [int.min, 0, 0];
      d.miningProgress = 0.0f;
    }
  } else {
    if(app.verbose) SDL_Log(toStringz(format("Dwarf %s failed to reach %s from %s, requeueing", d.dwarfName, d.targetTile, d.tilePos)));
    miningQueue ~= d.targetTile;
    d.targetTile = [int.min, 0, 0];
    d.miningProgress = 0.0f;
  }
}

void dwarfTick(ref App app, ref Geometry obj) {
  auto d = cast(Dwarf)obj;
  if(d is null) return;
  if(d.targetTile[0] != int.min && app.verbose){
    SDL_Log(toStringz(format("Dwarf %s @ tile %s target %s path:%d mining:%.0f", d.dwarfName, d.tilePos, d.targetTile, d.path.length, d.miningProgress * 100)));
  }

  if(d.targetTile[0] == int.min) app.claimJob(d);
  else if(d.path.length > 0) app.followPath(d);
  else app.doMining(d);
}

void spawnDwarf(ref App app, string name) {
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  Dwarf dwarf = new Dwarf();
  dwarf.dwarfName = name;
  dwarf.tilePos = tile;
  auto wp = app.tileToWorld(tile);
  dwarf.position([wp[0], wp[1] - 0.5f, wp[2]]);
  dwarf.setColor([uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), 1.0f]);
  dwarf.onTick = &dwarfTick;
  app.objects ~= dwarf;
}

