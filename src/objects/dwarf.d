/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;
import geometry;
import search : performSearch, atGoal, stepThroughPath;
import world : setTile,deriveInventory;
import vector : euclidean;
import tileatlas : tileData;

struct BuildJob {
  int[3] tile;
  TileType tileType;
}
BuildJob[] buildQueue;
int[3][] miningQueue;

/** Dwarven Cylinderz  */
class Dwarf : Cylinder {
  this() {
    name = (){ return(typeof(this).stringof); };
  }
  string dwarfName;
  int[3] tilePos    = [0, 0, 0];            /// Which tile we're on
  int[3] pickupTile = [int.min, 0, 0];      /// Dropped block to pick up
  int[3] targetTile = [int.min, 0, 0];      /// Where we are going
  float[3][] path;                          /// Path we're on
  float miningProgress = 0.0f;              /// Mining progress
  BuildJob currentBuild;                    /// Active build job
  float[3] visualPos = [0.0f, 0.0f, 0.0f];  /// Current interpolated position
  float[3] moveFrom = [0.0f, 0.0f, 0.0f];   /// World pos at start of move
  float[3] moveTo = [0.0f, 0.0f, 0.0f];     /// World pos at end of move
  float moveT = 1.0f;                       /// 1.0 = arrived, 0.0 = just started
}

class DroppedBlocks : Cube {
  int[3][] tilePos;

  this() {
    super();
    instancedMesh = true;
    instances = [];
    name = (){ return "DroppedBlocks"; };
  }
}

/** Is the Tile occupied ?  */
bool isTileOccupied(ref App app, int[3] tile) {
  foreach(o; app.objects) { auto d = cast(Dwarf)o; if(d !is null && d.tilePos == tile) return true; }
  return false;
}

/** Random names */
string randomDwarfName() {
  string[] prefixes = ["Urist", "Iden", "Meng", "Reg", "Doren", "Ast", "Nil", "Erib", "Thob", "Cog"];
  string[] suffixes = ["ral", "dor", "zan", "kel", "tok", "mis", "bur", "ith", "gar", "lon"];
  return prefixes[uniform(0, prefixes.length)] ~ suffixes[uniform(0, suffixes.length)];
}

/** Can we stand on this Tile ? */
bool isStandable(World world, int[3] tile) {
  if (tile[1] <= 0 || tile[1] >= world.chunkHeight) return false;
  return world.getTileAt(tile) == TileType.None && world.getTileAt([tile[0], tile[1]-1, tile[2]]) != TileType.None;
}

/** Find a free surface tile (as in non-occupado) and on top of the world */
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
        if(tile[1] > 0 && !app.isTileOccupied([tile[0], tile[1]+1, tile[2]])) { return [tile[0], tile[1]+1, tile[2]]; }
      }
    }
  }
  return [int.min, 0, 0];
}

/** Find the closest standable neighbour (air tile with solid below) to the dwarf */
int[3] findGoalTile(ref App app, Dwarf d) {
  int[3] goalTile = [int.min, 0, 0];
  float bestDist = float.max;
  foreach(n; app.world.tileNeighbours(d.targetTile)[0..2] ~ app.world.tileNeighbours(d.targetTile)[4..6]) {
    if(!app.world.isStandable(n)) continue;
    float dist = abs(n[0]-d.tilePos[0]) + abs(n[2]-d.tilePos[2]);
    if(dist < bestDist) { bestDist = dist; goalTile = n; }
  }
  return goalTile;
}

/** Find the closest dropped block of the given TileType to the dwarf, returns tile or [int.min,0,0] */
int[3] findDroppedBlock(ref App app, TileType tt, int[3] dwarfTile) {
  if(app.world.droppedBlocks is null) return [int.min, 0, 0];
  int[3] best = [int.min, 0, 0];
  float bestDist = float.max;
  foreach(i, tile; app.world.droppedBlocks.tilePos) {
    if(app.world.droppedBlocks.instances[i].meshdef[0] != cast(uint)tt) continue;
    float dist = abs(tile[0] - dwarfTile[0]) + abs(tile[2] - dwarfTile[2]);
    if(dist < bestDist) { bestDist = dist; best = tile; }
  }
  return best;
}

/** Compute world-space position from tile coords */
float[3] tileToWorld(ref App app, int[3] tile) {
  auto wp = app.world.worldPos(tile);
  return [wp[0], wp[1] + app.world.yOffset, wp[2]];
}

/** Scan the queue, claim the closest reachable job and remove it from the queue, returns false if no job could be claimed */
bool claimBestJob(ref App app, Dwarf d, out int[3] goalTile) {
  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, job; miningQueue) {
    d.targetTile = job;
    auto goal = app.findGoalTile(d);
    if(goal[0] == int.min) continue;
    float dist = abs(goal[0] - d.tilePos[0]) + abs(goal[2] - d.tilePos[2]);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; goalTile = goal; }
  }
  if(bestIdx == -1) { d.targetTile = [int.min, 0, 0]; return(false); }
  d.targetTile = miningQueue[bestIdx];
  miningQueue = miningQueue[0..bestIdx] ~ miningQueue[bestIdx+1..$];
  return(true);
}

/** Pathfind dwarf to goalTile, returns false if unreachable */
bool pathfindTo(ref App app, Dwarf d, int[3] goalTile) {
  float[3] start = app.tileToWorld(d.tilePos);
  float[3] goal  = app.tileToWorld(goalTile);
  if(app.verbose) SDL_Log(toStringz(format("Dwarf %s pathfinding from %s to %s", d.dwarfName, start, goal)));
  auto result = performSearch!(World, PathNode)(start, goal, app.world, app.verbose > 0);
  if(app.verbose) SDL_Log(toStringz(format("Search: %s steps: %d", result.state, result.steps)));
  if(result.state == SearchState.FAILED || result.state == SearchState.INVALID) return false;
  d.path = [];
  while(result.pathptr != size_t.max && !result.atGoal()) d.path ~= result.stepThroughPath(app.trace);
  d.path ~= result.pool[result.goal].position;
  return true;
}

/** Claim a job, find goal tile, compute path */
bool claimJob(ref App app, Dwarf d) {
  int[3] goalTile;
  if(!app.claimBestJob(d, goalTile)) return false;
  if(!app.pathfindTo(d, goalTile)) { d.targetTile = [int.min, 0, 0]; return false; }
  return true;
}

bool claimBuildJob(ref App app, Dwarf d) {
  foreach(i, ref job; buildQueue) {
    int[3] blockTile = app.findDroppedBlock(job.tileType, d.tilePos);
    if(blockTile[0] == int.min) continue;
    if(!app.pathfindTo(d, blockTile)) continue;
    d.currentBuild = job;
    d.pickupTile = blockTile;
    d.targetTile = blockTile;
    buildQueue = buildQueue[0..i] ~ buildQueue[i+1..$];
    return true;
  }
  return false;
}

void doPickup(ref App app, Dwarf d) {
  auto db = app.world.droppedBlocks;
  foreach(i, tile; db.tilePos) {
    if(tile == d.pickupTile && db.instances[i].meshdef[0] == cast(uint)d.currentBuild.tileType) {
      db.tilePos = db.tilePos[0..i] ~ db.tilePos[i+1..$];
      db.instances = db.instances[0..i] ~ db.instances[i+1..$];
      db.buffers[INSTANCE] = false;
      break;
    }
  }
  app.deriveInventory();
  d.pickupTile = [int.min, 0, 0];
  d.targetTile = d.currentBuild.tile;
  auto goalTile = app.findGoalTile(d);
  if(goalTile[0] == int.min || !app.pathfindTo(d, goalTile)) {
    SDL_Log(toStringz(format("Dwarf %s can't reach build site %s, requeueing", d.dwarfName, d.currentBuild.tile)));
    buildQueue ~= d.currentBuild;
    d.currentBuild = BuildJob.init;
    d.targetTile = [int.min, 0, 0];
  }
}

/** Place the tile at the build site */
void doBuilding(ref App app, Dwarf d) {
  auto dx = abs(d.tilePos[0] - d.currentBuild.tile[0]);
  auto dz = abs(d.tilePos[2] - d.currentBuild.tile[2]);
  if(dx + dz == 1 && d.tilePos[1] == d.currentBuild.tile[1]) {
    app.setTile(d.currentBuild.tile, d.currentBuild.tileType);
    if(app.verbose) SDL_Log(toStringz(format("Dwarf %s built %s at %s", d.dwarfName, d.currentBuild.tileType, d.currentBuild.tile)));
    d.currentBuild = BuildJob.init;
    d.targetTile = [int.min, 0, 0];
  } else {
    SDL_Log(toStringz(format("Dwarf %s failed to reach build site %s, requeueing", d.dwarfName, d.currentBuild.tile)));
    buildQueue ~= d.currentBuild;
    d.currentBuild = BuildJob.init;
    d.targetTile = [int.min, 0, 0];
  }
}

/** Move dwarf one step along its path */
void followPath(ref App app, Dwarf d) {
  if (d.path.length == 0) return;
  auto next = d.path[0];
  d.path = d.path[1..$];
  d.moveFrom = d.visualPos;
  d.moveTo   = [next[0], next[1] - 0.5f, next[2]];
  d.moveT    = 0.0f;
  d.tilePos  = app.world.worldToTile(next);   /// logical position updates immediately, chains next step
}

/** dwarfFrame */
void dwarfFrame(ref App app, ref Geometry obj, float dt) {
  auto d = cast(Dwarf)obj;
  if (d is null || d.moveT >= 1.0f) return;
  d.moveT = min(1.0f, d.moveT + dt * 2.0f);
  float t = d.moveT * d.moveT * (3.0f - 2.0f * d.moveT);
  d.visualPos = [
    d.moveFrom[0] + t * (d.moveTo[0] - d.moveFrom[0]),
    d.moveFrom[1] + t * (d.moveTo[1] - d.moveFrom[1]),
    d.moveFrom[2] + t * (d.moveTo[2] - d.moveFrom[2])
  ];
  d.position(d.visualPos);
  if (d.moveT >= 1.0f && d.path.length > 0) app.followPath(d);
}

/** dwarfTick */
void dwarfTick(ref App app, ref Geometry obj) {
  auto d = cast(Dwarf)obj;
  if(d is null) return;
  if(d.targetTile[0] != int.min && app.verbose){
    SDL_Log(toStringz(format("Dwarf %s @ tile %s target %s path:%d mining:%.0f", d.dwarfName, d.tilePos, d.targetTile, d.path.length, d.miningProgress * 100)));
  }

  if(d.targetTile[0] == int.min) {
    if(!app.claimJob(d)) app.claimBuildJob(d);
  } else if(d.path.length > 0 && d.moveT >= 1.0f) {
    app.followPath(d);
  } else if(d.path.length == 0 && d.moveT >= 1.0f) {
    if(d.pickupTile[0] != int.min) app.doPickup(d);
    else if(d.currentBuild.tileType != TileType.None) app.doBuilding(d);
    else app.doMining(d);
  }
}

Instance toDropInstance(ref App app, int[3] tile, TileType tt) {
  float ts = app.world.tileSize * 0.25f;
  float th = app.world.tileHeight * 0.25f;
  auto wp = app.tileToWorld(tile);
  wp[1] -= (app.world.tileHeight - th) * 0.5f;
  return Instance(cast(uint)tt, [ts,0,0, 0,th,0, 0,0,ts, wp[0],wp[1],wp[2]]);
}

void spawnDroppedBlock(ref App app, int[3] tile, TileType tt) {
  if(app.world.droppedBlocks is null) return;
  app.world.droppedBlocks.tilePos ~= tile;
  app.world.droppedBlocks.instances ~= app.toDropInstance(tile, tt);
  app.world.droppedBlocks.buffers[INSTANCE] = false;
  app.deriveInventory();
}

/** Mine the target tile if adjacent */
void doMining(ref App app, Dwarf d) {
  auto dx = abs(d.tilePos[0] - d.targetTile[0]);
  auto dz = abs(d.tilePos[2] - d.targetTile[2]);
  if(dx + dz == 1 && d.tilePos[1] == d.targetTile[1]) {
    d.miningProgress += 0.25f;
    if(app.verbose) SDL_Log(toStringz(format("Dwarf %s mining %s %.0f%%", d.dwarfName, d.targetTile, d.miningProgress * 100)));
    if(d.miningProgress >= 1.0f) {
      TileType tt = app.world.getTileAt(d.targetTile);
      app.setTile(d.targetTile);
      app.spawnDroppedBlock(d.targetTile, tt);
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

/** Spawn a Dwarf */
void spawnDwarf(ref App app, string name) {
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  Dwarf dwarf = new Dwarf();
  dwarf.dwarfName = name;
  dwarf.tilePos = tile;
  auto wp = app.tileToWorld(tile);
  dwarf.position([wp[0], wp[1] - 0.5f, wp[2]]);
  dwarf.visualPos = [wp[0], wp[1] - 0.5f, wp[2]];
  dwarf.moveFrom  = dwarf.visualPos;
  dwarf.moveTo = dwarf.visualPos;
  dwarf.moveT = 1.0f;
  dwarf.setColor([uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), 1.0f]);
  dwarf.onFrame = &dwarfFrame;
  dwarf.onTick = &dwarfTick;
  app.objects ~= dwarf;
}

