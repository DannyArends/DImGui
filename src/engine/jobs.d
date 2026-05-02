/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : spawnBlock, findFreeBlock;
import pathfinding : findGoalTile, pathfindTo;
import inventory : deriveInventory;
import tree : fellTree;
import ghost : syncBuildGhosts;
import world : noTile, setTile, tileAbove;

struct Job {
  string name;
  int[3] targetTile;
  TileType tileType;
  uint[] blockIDs;         /// block IDs reserved/carried for this job
  Job[] prereqs;
  uint[] failedBy;

  void function(ref App app, ref Dwarf d, ref Job j) onClaim;
  void function(ref App app, ref Dwarf d) onArrive;
  void function(ref App app, ref Dwarf d) onFail;
}

Job[] jobQueue;

/** Apply pathfinding results */
void applyPathResult(ref App app, PathResult result) {
  if(app.world.dwarves is null) return;
  foreach(ref d; app.world.dwarves) {
    if(d.uid != result.dwarfUID) continue;
    if(!result.success) {
      if(d.jobStack.length > 0) {
        d.jobStack[$-1].failedBy ~= d.uid;
        d.jobStack[0].onFail(app, d);
      }
      return;
    }
    d.waitingForPath = false;
    d.path = result.path;
    d.moveFrom = d.visualPos;
    d.moveTo = d.visualPos;
    d.moveT = 1.0f;
    return;
  }
}

/** Mining Job */
Job miningJob(int[3] targetTile, uint retries = 3) {
  return Job("Mining", targetTile, TileType.None, [],
    onArrive: (ref App app, ref Dwarf d) {
      d.miningProgress += 0.25f;
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s mining %s %.0f%%", d.name, d.jobStack[0].targetTile, d.miningProgress * 100)));
      if(d.miningProgress >= 1.0f) {
        TileType tt = app.world.getTileAt(d.jobStack[0].targetTile);
        app.setTile(d.jobStack[0].targetTile);
        app.fellTree(d.jobStack[0].targetTile.tileAbove);
        if(tt != TileType.None) app.spawnBlock(d.jobStack[0].targetTile, tt);
        app.deriveInventory();
        app.world.pendingUnsettle ~= d.jobStack[0].targetTile;
        d.jobStack = d.jobStack[1..$];
        d.clearGoal();
        d.miningProgress = 0.0f;
      }
    },
    onFail: (ref App app, ref Dwarf d) { d.failAndRequeue(); }
  );
}

Job stuffJob() { return pickupJob(noTile, TileType.None); }

/** woodcutting Job */
Job woodcuttingJob(int[3] targetTile) {
  return Job("Woodcutting", targetTile, TileType.None, [],
    onArrive: (ref App app, ref Dwarf d) {
      d.miningProgress += 0.25f;
      if(d.miningProgress >= 1.0f) {
        app.fellTree(d.jobStack[0].targetTile);
        d.jobStack = d.jobStack[1..$];
        d.clearGoal();
        d.miningProgress = 0.0f;
      }
    },
    onFail: (ref App app, ref Dwarf d) { d.failAndRequeue(); }
  );
}

/** Pickup Job */
Job pickupJob(int[3] targetTile, TileType tileType) {
  return Job("Fetching", targetTile, tileType, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) {
      auto id = app.findFreeBlock(d.tile, j.tileType);
      if(id == noBlock) { j.targetTile = noTile; return; }
      j.blockIDs = [id];
      foreach(ref b; app.world.blocks.blocks) { if(b.id == id) { j.targetTile = b.tile; return; } }
      j.targetTile = noTile;
    },
    onArrive: (ref App app, ref Dwarf d) { app.doPickup(d); },
    onFail: (ref App app, ref Dwarf d) {
      if(app.verbose) SDL_Log(toStringz(format("[Job] %s FAILED %s (tileType=%s)", d.name, d.jobStack[0].name, d.jobStack[0].tileType)));
      d.failAndRequeueParent();
    }
  );
}

Job moveAwayJob(int[3] from) {
  return Job("MoveAway", from, TileType.None, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) {
      foreach(n; app.world.tileNeighbours(j.targetTile)[0..2] ~ app.world.tileNeighbours(j.targetTile)[4..6]) {
        if(app.world.isStandable(n)) { j.targetTile = n; return; }
      }
      j.targetTile = noTile;  // nowhere to go, skip
    },
    onArrive: (ref App app, ref Dwarf d) {
      d.jobStack = d.jobStack[1..$];
      d.clearGoal();
    },
    onFail: (ref App app, ref Dwarf d) {
      d.jobStack = d.jobStack[1..$];
      d.clearGoal();
    }
  );
}

Job holdItemJob(TileType tileType) {
  return Job("HoldItem", [int.min, 0, 0], tileType, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) {
      foreach(id; d.carrying) {
        foreach(ref b; app.world.blocks.blocks) {
          if(b.id == id && b.type == j.tileType) { j.targetTile = noTile; return; }  // already carrying
        }
      }
      auto id = app.findFreeBlock(d.tile, j.tileType);
      if(id == noBlock) { j.targetTile = noTile; return; }
      j.blockIDs = [id];
      foreach(ref b; app.world.blocks.blocks) { if(b.id == id) { j.targetTile = b.tile; return; } }
      j.targetTile = noTile;
    },
    onArrive: (ref App app, ref Dwarf d) {
      foreach(id; d.carrying) {
        foreach(ref b; app.world.blocks.blocks) {
          if(b.id == id && b.type == d.jobStack[0].tileType) {
            d.jobStack = d.jobStack[1..$];
            d.clearGoal();
            return;
          }
        }
      }
      app.doPickup(d);
    },
    onFail: (ref App app, ref Dwarf d) {
      if(app.verbose) SDL_Log(toStringz(format("[Job] %s FAILED %s (tileType=%s)", d.name, d.jobStack[0].name, d.jobStack[0].tileType)));
      d.failAndRequeueParent();
    }
  );
}
/** Move to a free neighbouring tile and drops a carried block */
Job dropBlockJob(int[3] fromTile, uint blockID) {
  return Job("DropBlock", fromTile, TileType.None, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) {
      foreach(n; app.world.tileNeighbours(j.targetTile)[0..2] ~ app.world.tileNeighbours(j.targetTile)[4..6]) {
        if(app.world.isStandable(n)) { j.targetTile = n; return; }
      }
      j.targetTile = noTile;
    },
    onArrive: (ref App app, ref Dwarf d) {
      foreach(i, id; d.carrying) {
        if(id == d.jobStack[0].blockIDs[0]) { d.drop(app, i); break; }
      }
      d.jobStack = d.jobStack[1..$];
      d.clearGoal();
    },
    onFail: (ref App app, ref Dwarf d) {
      d.jobStack = d.jobStack[1..$];
      d.clearGoal();
    }
  );
}

/** Clean the worksite (generates a pickup job prereq) */
Job cleanWorksiteJob(int[3] targetTile) {
  return Job("CleanWorksite", targetTile, TileType.None, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) {
      if(app.world.blocks !is null) {
        foreach(ref b; app.world.blocks.blocks) {
          if(b.tile == j.targetTile) { j.blockIDs = [b.id]; j.tileType = b.type; return; }
        }
      }
      j.targetTile = noTile;
    },
    onArrive: (ref App app, ref Dwarf d) {
      if(d.carrying.length >= d.inventory.length) {
        d.jobStack = [dropBlockJob(d.tile, d.carrying[0])] ~ d.jobStack;
      } else { app.doPickup(d); }
    },
    onFail: (ref App app, ref Dwarf d) {
      d.jobStack = d.jobStack[1..$];
      d.clearGoal();
    }
  );
}

/** Building Job (generates a pickup job prereq) */
Job buildingJob(int[3] targetTile, TileType tileType) {
  return Job("Building", targetTile, tileType, [cleanWorksiteJob(targetTile), holdItemJob(tileType)],
    onArrive: (ref App app, ref Dwarf d) {
      // find carried block of correct type
      uint blockID = noBlock;
      foreach(id; d.carrying) {
        foreach(ref b; app.world.blocks.blocks) {
          if(b.id == id && b.type == d.jobStack[0].tileType) { blockID = id; break; }
        }
        if(blockID != noBlock) break;
      }
      if(blockID == noBlock) { d.jobStack[0].onFail(app, d); return; }
      if(!d.use(blockID)) { d.jobStack[0].onFail(app, d); return; }
      // mark block as InChunk — update its tile to build site
      foreach(ref b; app.world.blocks.blocks) {
        if(b.id == blockID) { b.tile = d.jobStack[0].targetTile; break; }
      }
      if(app.world.dwarves !is null) {
        foreach(ref other; app.world.dwarves.dwarves) {
          if(other.tile == d.jobStack[0].targetTile) { other.jobStack = [moveAwayJob(other.tile)] ~ other.jobStack; }
        }
      }
      app.setTile(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      app.syncBlockInstances();
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s built %s at %s", d.name, d.jobStack[0].tileType, d.jobStack[0].targetTile)));
      d.jobStack = d.jobStack[1..$];
      d.clearGoal();
      app.syncBuildGhosts();
      app.deriveInventory();
    },
    onFail: (ref App app, ref Dwarf d) {
      if(app.verbose){
        SDL_Log(toStringz(format("[Job] %s FAILED Building %s at %s, requeueing", d.name, d.jobStack[0].tileType, d.jobStack[0].targetTile)));
      }
      foreach(i, id; d.carrying) d.drop(app, i);
      auto newJob = buildingJob(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      newJob.failedBy = d.jobStack[0].failedBy ~ [d.uid];
      jobQueue ~= newJob;
      d.jobStack = [];
      d.clearGoal();
      app.syncBuildGhosts();
    }
  );
}

/** Dispatch a job to a dwarf */
bool dispatchJob(ref App app, ref Dwarf d, ref Job job) {
  if(app.verbose) SDL_Log(toStringz(format("[Job] %s claimed '%s' targeting %s", d.name, job.name, job.targetTile)));
  d.jobStack = job.prereqs ~ [job];
  foreach(ref j; d.jobStack) { if(j.onClaim !is null) j.onClaim(app, d, j); }
  d.jobStack = d.jobStack.filter!(j => j.targetTile != noTile).array;
  if(app.verbose) SDL_Log(toStringz(format("[Job] %s stack: %s", d.name, d.jobStack.map!(j => j.name).array)));
  if(d.jobStack.length == 0 || d.jobStack[0].targetTile == noTile) { d.jobStack = []; return false; }
  d.targetTile = d.jobStack[0].targetTile;
  auto goal = app.findGoalTile(d);
  if(goal == noTile || !app.pathfindTo(d, goal)) {
    job.failedBy ~= d.uid;
    jobQueue ~= job;
    d.jobStack = [];
    return false;
  }
  return true;
}

void doPickup(ref App app, ref Dwarf d) {
  auto blockID = d.jobStack[0].blockIDs.length > 0 ? d.jobStack[0].blockIDs[0] : noBlock;
  if(blockID == noBlock) { d.jobStack[0].onFail(app, d); return; }
  foreach(ref b; app.world.blocks.blocks) {
    if(b.id != blockID) continue;
    if(!d.pickup(blockID)) { d.jobStack[0].onFail(app, d); return; }
    b.tile = noTile;  // mark as carried
    app.syncBlockInstances();
    d.jobStack = d.jobStack[1..$];
    d.clearGoal();
    return;
  }
  // block not found
  if(d.jobStack.length > 1) jobQueue ~= d.jobStack[$-1];
  d.jobStack = [];
  d.clearGoal();
}

/** Try assigning a job to the closest idle dwarf */
bool tryAssign(ref App app, ref Job job) {
  if(app.world.dwarves is null) return false;
  Dwarf* best = null;
  float bestDist = float.max;
  foreach(ref d; app.world.dwarves) {
    if((!d.isIdle && !d.isWandering) || job.failedBy.canFind(d.uid)) continue;
    float dist = abs(job.targetTile[0] - d.tile[0]) + abs(job.targetTile[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; best = &d; }
  }
  return best !is null && app.dispatchJob(*best, job);
}

/** Fail the current job and requeue */
void failAndRequeue(ref Dwarf d) {
  auto j = d.jobStack[0];
  j.failedBy ~= d.uid;
  jobQueue ~= j;
  d.jobStack = [];
  d.clearGoal();
  d.miningProgress = 0.0f;
}

/** Fail the current job and requeue parent */
void failAndRequeueParent(ref Dwarf d) {
  if(d.jobStack.length > 1) jobQueue ~= d.jobStack[1];
  d.jobStack = [];
  d.clearGoal();
}

/** Allow a dwarf to select their next job */
void claimNextJob(ref App app, ref Dwarf d) {
  if(jobQueue.length == 0) return;
  size_t dwarfCount = app.world.dwarves !is null ? app.world.dwarves.length : 0;
  jobQueue = jobQueue.filter!(j => j.failedBy.length < dwarfCount).array;
  app.syncBuildGhosts();
  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref job; jobQueue) {
    if(job.failedBy.canFind(d.uid)) continue;
    if(job.targetTile == noTile) continue;
    if(job.name == "Building" && app.world.inventory.onFloor.get(job.tileType, 0) <= 0 && !d.carrying.any!(id => app.world.blocks.blocks.any!(b => b.id == id && b.type == job.tileType))) continue;
  float dist = abs(job.targetTile[0] - d.tile[0]) + abs(job.targetTile[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  if(bestIdx == -1) return;
  auto job = jobQueue[bestIdx];
  jobQueue = jobQueue[0..bestIdx] ~ jobQueue[bestIdx+1..$];
  if(app.dispatchJob(d, job)) app.deriveInventory();
}

