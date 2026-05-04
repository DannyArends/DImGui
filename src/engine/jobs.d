/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : spawnBlock, findFreeBlock, syncBlockInstances, noBlock, builtTile;
import pathfinding : findGoalTile, pathfindTo;
import inventory : deriveInventory;
import tree : fellTree;
import ghost : syncBuildGhosts;
import world : noTile, setTile, tileAbove;

enum JobState { Pending, Satisfied, Unavailable }

struct Job {
  string name;
  int[3] targetTile = noTile;
  TileType tileType;
  Job[] prereqs;
  uint[] blockIDs;
  uint[] failedBy;

  JobState state = JobState.Pending;

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
        if(!d.jobStack[0].failedBy.canFind(d.uid)) d.jobStack[0].failedBy ~= d.uid;
        if(d.jobStack.length > 1 && !d.jobStack[$-1].failedBy.canFind(d.uid)) d.jobStack[$-1].failedBy ~= d.uid;
        d.jobStack[0].onFail(app, d);
      }
      d.state = DwarfState.Idle;
      return;
    }
    d.state = (d.jobStack.length > 0) ? DwarfState.Moving : DwarfState.Wandering;
    d.path = result.path;
    d.moveTo = d.moveFrom = d.visualPos;
    d.moveT = 1.0f;
    return;
  }
}

/** Advance the job stack — removes the active sub-job and clears the dwarf's current goal */
void completeSubJob(ref Dwarf d) {
  d.jobStack = d.jobStack[1..$];
  d.targetTile = noTile;
  d.state = (d.jobStack.length > 0) ? DwarfState.Working : DwarfState.Idle;
}

void failSubJob(ref App app, ref Dwarf d) {
  SDL_Log(toStringz(format("[Job] %s FAILED %s (tileType=%s)", d.name, d.jobStack[0].name, d.jobStack[0].tileType)));
  d.failAndRequeueParent();
}

/** Advance progress on a task by amount; calls onComplete and completes the sub-job when progress reaches 1.0 */
void progressJob(ref App app, ref Dwarf d, float amount, void delegate() onComplete) {
  d.progress += amount;
  if(d.progress >= 1.0f) { onComplete(); d.completeSubJob(); d.progress = 0.0f; }
}

/** Returns the TileType of a block by ID, or TileType.None if not found */
TileType blockType(ref App app, uint id) { foreach(ref b; app.world.blocks.blocks) { if(b.id == id) return b.type; } return TileType.None; }

/** Claim the nearest free block of the required type for a job; sets j.targetTile to noTile if unavailable */
void claimBlock(ref App app, ref Dwarf d, ref Job j) {
  if(d.carrying.any!(id => app.blockType(id) == j.tileType)) { j.state = JobState.Satisfied; return; }
  auto id = app.findFreeBlock(d.tile, j.tileType);
  if(id == noBlock) { j.state = JobState.Unavailable; return; }
  j.blockIDs = [id];
  foreach(ref b; app.world.blocks.blocks) { if(b.id == id) { j.targetTile = b.tile; return; } }
  j.state = JobState.Unavailable;
}

/** Claim a standable neighbour tile adjacent to j.targetTile; sets j.targetTile to noTile if none found */
void claimNeighbour(ref App app, ref Job j) {
  foreach(n; app.world.tileNeighbours(j.targetTile)[0..2] ~ app.world.tileNeighbours(j.targetTile)[4..6]) {
    if(app.world.isStandable(n)) { j.targetTile = n; return; }
  }
  j.state = JobState.Satisfied;
}

/** Mining Job */
Job miningJob(int[3] targetTile, uint retries = 3) {
  return Job("Mining", targetTile, TileType.None, [],
    onArrive: (ref App app, ref Dwarf d) {
      app.progressJob(d, 0.25f, () {
        TileType tt = app.world.getTileAt(d.jobStack[0].targetTile);
        app.setTile(d.jobStack[0].targetTile);
        app.fellTree(d.jobStack[0].targetTile.tileAbove);
        if(tt != TileType.None) app.spawnBlock(d.jobStack[0].targetTile, tt);
        app.deriveInventory();
        app.world.pendingUnsettle ~= d.jobStack[0].targetTile;
      });
    },
    onFail: (ref App app, ref Dwarf d) { d.failAndRequeue(); }
  );
}

/** Convenience job: sends the dwarf to pick up any available block */
Job stuffJob() { return pickupJob(noTile, TileType.None); }

/** woodcutting Job */
Job woodcuttingJob(int[3] targetTile) {
  return Job("Woodcutting", targetTile, TileType.None, [],
    onArrive: (ref App app, ref Dwarf d) {
      app.progressJob(d, 0.25f, () { app.fellTree(d.jobStack[0].targetTile); });
    },
    onFail: (ref App app, ref Dwarf d) { d.failAndRequeue(); }
  );
}

/** Pickup Job */
Job pickupJob(int[3] targetTile, TileType tileType) {
  return Job("Fetching", targetTile, tileType, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) { app.claimBlock(d, j); },
    onArrive: (ref App app, ref Dwarf d) { app.doPickup(d); },
    onFail: (ref App app, ref Dwarf d) { 
      SDL_Log(toStringz(format("[pickupJob] %s FAILED %s", d.name, d.jobStack[0])));
      app.failSubJob(d);
    }
  );
}

/** Job: move the dwarf to a free neighbouring tile away from their current position */
Job moveAwayJob(int[3] from) {
  return Job("MoveAway", from, TileType.None, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) { app.claimNeighbour(j); },
    onArrive: (ref App app, ref Dwarf d) { d.completeSubJob(); },
    onFail: (ref App app, ref Dwarf d) { d.completeSubJob(); }
  );
}

/** Job: ensure the dwarf is carrying a block of the required type, fetching one if not */
Job holdItemJob(TileType tileType) {
  return Job("HoldItem", [int.min, 0, 0], tileType, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) { app.claimBlock(d, j); },
    onArrive: (ref App app, ref Dwarf d) {
      if(d.carrying.any!(id => app.blockType(id) == d.jobStack[0].tileType)) { d.completeSubJob(); return; }
      app.doPickup(d);
    },
    onFail: (ref App app, ref Dwarf d) { 
      SDL_Log(toStringz(format("[holdItemJob] %s FAILED %s", d.name, d.jobStack[0])));
      app.failSubJob(d); }
  );
}
/** Move to a free neighbouring tile and drops a carried block */
Job dropBlockJob(int[3] fromTile, uint blockID) {
  return Job("DropBlock", fromTile, TileType.None, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) { app.claimNeighbour(j); },
    onArrive: (ref App app, ref Dwarf d) {
      foreach(slot, id; d.inventory) { if(id == d.jobStack[0].blockIDs[0]) { d.drop(app, slot); break; } }
      d.completeSubJob();
    },
    onFail: (ref App app, ref Dwarf d) {
      SDL_Log(toStringz(format("[dropBlockJob] %s FAILED %s", d.name, d.jobStack[0])));
      d.completeSubJob();
    }
  );
}

/** Clean the worksite (generates a pickup job prereq) */
Job cleanWorksiteJob(int[3] targetTile) {
  return Job("CleanWorksite", targetTile, TileType.None, [],
    onClaim: (ref App app, ref Dwarf d, ref Job j) {
      if(app.world.blocks !is null) {
        foreach(ref b; app.world.blocks.blocks) { if(b.tile == j.targetTile) { j.blockIDs = [b.id]; j.tileType = b.type; return; } }
      }
      j.state = JobState.Satisfied;
    },
    onArrive: (ref App app, ref Dwarf d) {
      if(d.carrying.length >= d.inventory.length) {
        d.jobStack = [dropBlockJob(d.tile, d.carrying[0])] ~ d.jobStack;
      } else { app.doPickup(d); }
    },
    onFail: (ref App app, ref Dwarf d) { d.completeSubJob(); }
  );
}

/** Building Job (generates a pickup job prereq) */
Job buildingJob(int[3] targetTile, TileType tileType) {
  return Job("Building", targetTile, tileType, [cleanWorksiteJob(targetTile), holdItemJob(tileType)],
    onArrive: (ref App app, ref Dwarf d) {
      // find carried block of correct type
      auto found = d.carrying.filter!(id => app.blockType(id) == d.jobStack[0].tileType);
      if(found.empty) { d.jobStack[0].onFail(app, d); return; }
      if(!d.use(found.front)) { d.jobStack[0].onFail(app, d); return; }
      // mark block as InChunk — update its tile to build site
      foreach(ref b; app.world.blocks.blocks) { if(b.id == found.front) { b.tile = builtTile; break; } }
      if(app.world.dwarves !is null) {
        foreach(ref other; app.world.dwarves.dwarves) {
          if(other.tile == d.jobStack[0].targetTile) { other.jobStack = [moveAwayJob(other.tile)] ~ other.jobStack; }
        }
      }
      app.setTile(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      app.syncBlockInstances();
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s built %s at %s", d.name, d.jobStack[0].tileType, d.jobStack[0].targetTile)));
      d.completeSubJob();
      app.syncBuildGhosts();
      app.deriveInventory();
    },
    onFail: (ref App app, ref Dwarf d) {
      SDL_Log(toStringz(format("[Job] %s FAILED Building %s at %s, requeueing", d.name, d.jobStack[0].tileType, d.jobStack[0].targetTile)));
      foreach(slot, id; d.inventory) { if(id != noBlock) d.drop(app, slot); }
      auto newJob = buildingJob(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      newJob.failedBy = d.jobStack[0].failedBy ~ [d.uid];
      jobQueue ~= newJob;
      d.clearGoal();
      app.syncBuildGhosts();
    }
  );
}

/** Dispatch a job to a dwarf */
bool dispatchJob(ref App app, ref Dwarf d, Job job) {
  if(app.verbose) SDL_Log(toStringz(format("[Job] %s claimed '%s' targeting %s", d.name, job.name, job.targetTile)));
  d.jobStack = job.prereqs ~ [job];
  foreach(ref j; d.jobStack) { if(j.onClaim !is null) j.onClaim(app, d, j); }

  if(d.jobStack.any!(j => j.state == JobState.Unavailable)) {
    SDL_Log(toStringz(format("[Job] %s dispatch UNAVAILABLE for '%s'", d.name, job.name)));
    if(!job.failedBy.canFind(d.uid)) job.failedBy ~= d.uid;
    jobQueue ~= job;
    d.clearGoal();
    return false;
  }

  d.jobStack = d.jobStack.filter!(j => j.state != JobState.Satisfied).array;
  if(app.verbose) SDL_Log(toStringz(format("[Job] %s stack: %s", d.name, d.jobStack.map!(j => j.name).array)));

  if(d.jobStack.length == 0) { d.clearGoal(); return false; }
  d.targetTile = d.jobStack[0].targetTile;
  SDL_Log(toStringz(format("[Dispatch] %s first job='%s' targetTile=%s", d.name, d.jobStack[0].name, d.targetTile)));
  
  auto goal = app.findGoalTile(d);
  if(goal == noTile || !app.pathfindTo(d, goal)) {
    SDL_Log(toStringz(format("[Dispatch] %s PATH FAILED goal=%s for '%s' target=%s", d.name, goal, job.name, job.targetTile)));
    if(!job.failedBy.canFind(d.uid)) job.failedBy ~= d.uid;
    jobQueue ~= job;
    d.clearGoal();
    return false;
  }
  d.state = DwarfState.WaitingForPath;
  return true;
}

/** Execute a block pickup for the active job; marks the block as carried and completes the sub-job */
void doPickup(ref App app, ref Dwarf d) {
  auto blockID = d.jobStack[0].blockIDs.length > 0 ? d.jobStack[0].blockIDs[0] : noBlock;
  if(blockID == noBlock) { d.jobStack[0].onFail(app, d); return; }
  foreach(ref b; app.world.blocks.blocks) {
    if(b.id != blockID) continue;
    if(!d.pickup(blockID)) { d.jobStack[0].onFail(app, d); return; }
    b.tile = noTile;  // mark as carried
    app.syncBlockInstances();
    d.completeSubJob();
    return;
  }
  // block not found
  if(d.jobStack.length > 1) jobQueue ~= d.jobStack[$-1];
  d.clearGoal();
}

/** Try assigning a job to the closest idle dwarf */
bool tryAssign(ref App app, ref Job job) {
  if(app.world.dwarves is null) return false;
  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref d; app.world.dwarves.dwarves) {
    if((d.state != DwarfState.Idle && d.state != DwarfState.Wandering) || job.failedBy.canFind(d.uid)) continue;
    float dist = abs(job.targetTile[0] - d.tile[0]) + abs(job.targetTile[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  return bestIdx >= 0 && app.dispatchJob(app.world.dwarves.dwarves[bestIdx], job);
}

/** Fail the current job and requeue */
void failAndRequeue(ref Dwarf d) {
  auto j = d.jobStack[0];
  if(!j.failedBy.canFind(d.uid)) j.failedBy ~= d.uid;
  jobQueue ~= j;
  d.clearGoal();
  d.progress = 0.0f;
}

/** Fail the current job and requeue parent */
void failAndRequeueParent(ref Dwarf d) {
  if(d.jobStack.length > 1) jobQueue ~= d.jobStack[$-1];
  d.clearGoal();
}

/** Allow a dwarf to select their next job */
void claimNextJob(ref App app, ref Dwarf d) {
  size_t dwarfCount = app.world.dwarves !is null ? app.world.dwarves.length : 0;
  auto prevLen = jobQueue.length;
  jobQueue = jobQueue.filter!(j => j.failedBy.length < dwarfCount).array;
  if(jobQueue.length != prevLen) SDL_Log(toStringz(format("[Queue] %d jobs removed (failedBy filter), dwarfCount=%d", cast(int)(prevLen - jobQueue.length), cast(int)dwarfCount)));
  app.syncBuildGhosts();

  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref job; jobQueue) {
    if(job.failedBy.canFind(d.uid)) continue;
    if(job.name == "Building" && app.world.inventory.total(job.tileType, app.world.blocks) <= 0) continue;
    float dist = abs(job.targetTile[0] - d.tile[0]) + abs(job.targetTile[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  if(bestIdx != -1) {
    auto job = jobQueue[bestIdx];
    SDL_Log(toStringz(format("[Claim] %s taking '%s' tileType=%s failedBy=%d", d.name, job.name, job.tileType, cast(int)job.failedBy.length)));
    jobQueue = jobQueue[0..bestIdx] ~ jobQueue[bestIdx+1..$];
    if(app.dispatchJob(d, job)) { app.deriveInventory(); }
    return;
  }

  // No job found — wander or pick up stuff
  if(++d.idleTicks[0] > d.idleTicks[1]) {
    d.idleTicks[0] = 0;
    if(app.world.blocks !is null && app.world.blocks.blocks.length > 0 && d.carrying.length < (d.inventory.length / 2) && uniform(0, 10) == 0) {
      app.dispatchJob(d, stuffJob());
    } else {
      int[3] wander = [d.tile[0] + uniform(-3, 3), d.tile[1], d.tile[2] + uniform(-3, 3)];
      if(app.pathfindTo(d, wander)) d.targetTile = wander;
    }
  }
}
