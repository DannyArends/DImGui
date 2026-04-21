/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : spawnDroppedBlock, findFreeBlock, hasBlocks;
import pathfinding : findGoalTile, pathfindTo;
import inventory : deriveInventory;
import world : setTile;

struct Job {
  string name;
  int[3] targetTile;
  TileType tileType;
  Job[] prereqs;
  uint[] failedBy;

  void function(ref App app, Dwarf d, ref Job j) onClaim;
  void function(ref App app, Dwarf d) onArrive;
  void function(ref App app, Dwarf d) onFail;
}
Job[] jobQueue;

Job miningJob(int[3] targetTile, uint retries = 3) {
  return Job("Mining", targetTile, TileType.None, [],
    onArrive: (ref App app, Dwarf d) {
      d.miningProgress += 0.25f;
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s mining %s %.0f%%", d.name, d.jobStack[0].targetTile, d.miningProgress * 100)));
      if(d.miningProgress >= 1.0f) {
        TileType tt = app.world.getTileAt(d.jobStack[0].targetTile);
        app.setTile(d.jobStack[0].targetTile);
        if(tt != TileType.None) app.spawnDroppedBlock(d.jobStack[0].targetTile, tt);
        d.jobStack = d.jobStack[1..$];
        d.targetTile = [int.min, 0, 0];
        d.miningProgress = 0.0f;
      }
    },
    onFail: (ref App app, Dwarf d) {
      auto j = d.jobStack[0];
      j.failedBy ~= d.uid;
      jobQueue ~= j;
      d.jobStack = [];
      d.targetTile = [int.min, 0, 0];
      d.miningProgress = 0.0f;
    },
  );
}

Job pickupJob(int[3] targetTile, TileType tileType) {
  return Job("Fetching", targetTile, tileType, [],
    onClaim: (ref App app, Dwarf d, ref Job j) {
      j.targetTile = app.findFreeBlock(j.tileType, d.tile);
    },
    onArrive: (ref App app, Dwarf d) {
      auto db = app.world.droppedBlocks;
      foreach(i, tile; db.tiles) {
        if(tile == d.jobStack[0].targetTile) {
          db.tiles = db.tiles[0..i] ~ db.tiles[i+1..$];
          db.instances = db.instances[0..i] ~ db.instances[i+1..$];
          db.buffers[INSTANCE] = false;
          app.deriveInventory();
          d.carrying ~= d.jobStack[0].tileType;
          d.jobStack = d.jobStack[1..$];
          d.targetTile = [int.min, 0, 0];
          return;
        }
      }
      // block gone — requeue the building job (rest of stack)
      if(d.jobStack.length > 1) jobQueue ~= d.jobStack[1];
      d.jobStack = [];
      d.targetTile = [int.min, 0, 0];
    },
    onFail: (ref App app, Dwarf d) {
      if(d.jobStack.length > 1) {
        int[3] freeBlock = app.findFreeBlock(d.jobStack[0].tileType, d.tile);
        if(freeBlock[0] != int.min) jobQueue ~= d.jobStack[1];
      }
      d.jobStack = [];
      d.targetTile = [int.min, 0, 0];
    }
  );
}

Job buildingJob(int[3] targetTile, TileType tileType) {
  return Job("Building", targetTile, tileType, [pickupJob([int.min, 0, 0], tileType)],
    onArrive: (ref App app, Dwarf d) {
      app.setTile(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s built %s at %s", d.name, d.jobStack[0].tileType, d.jobStack[0].targetTile)));
      d.carrying = d.carrying.remove!(c => c == d.jobStack[0].tileType);
      d.jobStack = d.jobStack[1..$];
      d.targetTile = [int.min, 0, 0];
    },
    onFail: (ref App app, Dwarf d) {
      foreach(tt; d.carrying) app.spawnDroppedBlock(d.tile, tt);
      d.carrying = [];
      jobQueue ~= buildingJob(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      d.jobStack = [];
      d.targetTile = [int.min, 0, 0];
    }
  );
}

void claimNextJob(ref App app, Dwarf d) {
  if(jobQueue.length == 0) return;
  size_t dwarfCount = app.objects.count!(o => cast(Dwarf)o !is null);
  jobQueue = jobQueue.filter!(j => j.failedBy.length < dwarfCount).array;
  if(jobQueue.length == 0) return;

  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref job; jobQueue) {
    if(job.failedBy.canFind(d.uid)) continue;
    d.targetTile = job.targetTile;
    auto goal = app.findGoalTile(d);
    if(goal[0] == int.min) { job.failedBy ~= d.uid; continue; }
    float dist = abs(goal[0] - d.tile[0]) + abs(goal[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  if(bestIdx == -1) { d.targetTile = [int.min, 0, 0]; return; }

  auto job = jobQueue[bestIdx];
  jobQueue = jobQueue[0..bestIdx] ~ jobQueue[bestIdx+1..$];

  d.jobStack = job.prereqs ~ [job];

  foreach(ref j; d.jobStack) { if(j.onClaim !is null) j.onClaim(app, d, j); }

  if(d.jobStack[0].targetTile[0] == int.min) { d.jobStack[0].onFail(app, d); return; }

  d.targetTile = d.jobStack[0].targetTile;
  auto goalTile = app.findGoalTile(d);
  if(goalTile[0] == int.min || !app.pathfindTo(d, goalTile)) { d.jobStack[0].onFail(app, d); }
}

