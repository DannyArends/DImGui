/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : spawnDroppedBlock, findDroppedBlock;
import dwarf : findGoalTile, pathfindTo;
import inventory : deriveInventory;
import world : setTile;

struct BuildJob {
  int[3] tile;
  TileType tileType;
}
BuildJob[] buildQueue;
int[3][] miningQueue;


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

/** Claim a job, find goal tile, compute path */
bool claimJob(ref App app, Dwarf d) {
  int[3] goalTile;
  if(!app.claimBestJob(d, goalTile)) return false;
  if(!app.pathfindTo(d, goalTile)) { d.targetTile = [int.min, 0, 0]; return false; }
  return true;
}

/** Claim a Build job */
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

/** Pickup */
void doPickup(ref App app, Dwarf d) {
  auto db = app.world.droppedBlocks;
  foreach(i, tile; db.tilePos) {
    if(tile == d.pickupTile) {
      auto dx = abs(d.tilePos[0] - tile[0]);
      auto dz = abs(d.tilePos[2] - tile[2]);
      if(dx + dz > 1) return;
      db.tilePos = db.tilePos[0..i] ~ db.tilePos[i+1..$];
      db.instances = db.instances[0..i] ~ db.instances[i+1..$];
      db.buffers[INSTANCE] = false;
      app.deriveInventory();
      d.pickupTile = [int.min, 0, 0];
      d.targetTile = [int.min, 0, 0];
      return;
    }
  }
  // block gone
  d.currentBuild = BuildJob.init;
  d.pickupTile = [int.min, 0, 0];
  d.targetTile = [int.min, 0, 0];
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
      if(tt != TileType.None) app.spawnDroppedBlock(d.targetTile, tt);
      d.targetTile = [int.min, 0, 0];
      d.miningProgress = 0.0f;
    }
  } else {
    d.targetTile = d.targetTile; // keep target
    auto goalTile = app.findGoalTile(d);
    if(goalTile[0] == int.min || !app.pathfindTo(d, goalTile)) {
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s can't reach %s, requeueing", d.dwarfName, d.targetTile)));
      miningQueue ~= d.targetTile;
      d.targetTile = [int.min, 0, 0];
      d.miningProgress = 0.0f;
    }
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
  } else { // try to re-path
    d.targetTile = d.currentBuild.tile;
    auto goalTile = app.findGoalTile(d);
    if(goalTile[0] == int.min || !app.pathfindTo(d, goalTile)) {
      SDL_Log(toStringz(format("Dwarf %s can't reach build site %s, dropping block", d.dwarfName, d.currentBuild.tile)));
      app.spawnDroppedBlock(d.tilePos, d.currentBuild.tileType);
      buildQueue ~= d.currentBuild;
      d.currentBuild = BuildJob.init;
      d.targetTile = [int.min, 0, 0];
    }
  }
}

