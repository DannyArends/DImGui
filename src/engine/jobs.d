/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : spawnDroppedBlock, findDroppedBlock;
import pathfinding : findGoalTile, pathfindTo;
import inventory : deriveInventory;
import world : setTile;

struct Job {
  string name;
  int[3] targetTile;
  TileType tileType;                              // for building/pickup context
  int[3] pickupTile;                             // for build jobs
  void function(ref App app, Dwarf d) onArrive;
  void function(ref App app, Dwarf d) onFail;
}

Job[] jobQueue;

Job miningJob(int[3] targetTile) {
  return Job("Mining", targetTile, TileType.None, [int.min, 0, 0],
    (ref App app, Dwarf d) {
      d.miningProgress += 0.25f;
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s mining %s %.0f%%", d.name, d.currentJob.targetTile, d.miningProgress * 100)));
      if(d.miningProgress >= 1.0f) {
        TileType tt = app.world.getTileAt(d.currentJob.targetTile);
        app.setTile(d.currentJob.targetTile);
        if(tt != TileType.None) app.spawnDroppedBlock(d.currentJob.targetTile, tt);
        d.currentJob = Job.init;
        d.targetTile = [int.min, 0, 0];
        d.miningProgress = 0.0f;
      }
    },
    (ref App app, Dwarf d) {
      jobQueue ~= miningJob(d.currentJob.targetTile);
      d.currentJob = Job.init;
      d.targetTile = [int.min, 0, 0];
      d.miningProgress = 0.0f;
    }
  );
}

Job pickupJob(int[3] targetTile, TileType tileType, int[3] buildTile) {
  return Job("Fetching", targetTile, tileType, buildTile,
    (ref App app, Dwarf d) {
      auto db = app.world.droppedBlocks;
      foreach(i, tile; db.tiles) {
        if(tile == d.currentJob.targetTile) {
          db.tiles = db.tiles[0..i] ~ db.tiles[i+1..$];
          db.instances = db.instances[0..i] ~ db.instances[i+1..$];
          db.buffers[INSTANCE] = false;
          app.deriveInventory();
          // chain to build job
          d.currentJob = buildingJob(d.currentJob.pickupTile, d.currentJob.tileType);
          d.targetTile = [int.min, 0, 0];
          return;
        }
      } // block gone, abandon
      d.currentJob = Job.init;
      d.targetTile = [int.min, 0, 0];
    },
    (ref App app, Dwarf d) { // can't reach block, requeue build job
      jobQueue ~= buildingJob(d.currentJob.pickupTile, d.currentJob.tileType);
      d.currentJob = Job.init;
      d.targetTile = [int.min, 0, 0];
    }
  );
}

Job buildingJob(int[3] targetTile, TileType tileType) {
  return Job("Building", targetTile, tileType, [int.min, 0, 0],
    (ref App app, Dwarf d) {
      app.setTile(d.currentJob.targetTile, d.currentJob.tileType);
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s built %s at %s", d.name, d.currentJob.tileType, d.currentJob.targetTile)));
      d.currentJob = Job.init;
      d.targetTile = [int.min, 0, 0];
    },
    (ref App app, Dwarf d) {
      // can't reach build site, drop block and requeue
      app.spawnDroppedBlock(d.tile, d.currentJob.tileType);
      jobQueue ~= buildingJob(d.currentJob.targetTile, d.currentJob.tileType);
      d.currentJob = Job.init;
      d.targetTile = [int.min, 0, 0];
    }
  );
}

void claimNextJob(ref App app, Dwarf d) {
  if(jobQueue.length == 0) return;
  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref job; jobQueue) {
    d.targetTile = job.targetTile;
    auto goal = app.findGoalTile(d);
    if(goal[0] == int.min) continue;
    float dist = abs(goal[0] - d.tile[0]) + abs(goal[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  if(bestIdx == -1) { d.targetTile = [int.min, 0, 0]; return; }
  d.currentJob = jobQueue[bestIdx];
  jobQueue = jobQueue[0..bestIdx] ~ jobQueue[bestIdx+1..$];
  d.targetTile = d.currentJob.targetTile;
  auto goalTile = app.findGoalTile(d);
  if(goalTile[0] == int.min || !app.pathfindTo(d, goalTile)) { d.currentJob.onFail(app, d); }
}

