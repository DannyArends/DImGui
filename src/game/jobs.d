/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock, hasBlocks, findFreeBlock, syncBlockInstances, noBlock;
import feature : interactFeaturesAt, getFeatureProgressRate;
import pathfinding : pathfindTo, findGoalTile;
import tile : setTile, tileAbove, getTileAt, isStandable, isTileOccupied;
import timing : timed;
import vector : manhattan, manhattan2D;


enum JobState { Pending, Satisfied, Unavailable }
enum Reach { Adjacent, OnTile } 

struct Job {
  string name;
  int[3] targetTile = noTile;
  ResourceType tileType;
  Job[] prereqs;
  bool personal = false;
  uint[] blockIDs;
  bool[uint] failedBy;
  JobState state = JobState.Pending;
  Reach reach = Reach.Adjacent;

  bool function(ref GameApp app, ref Job j) isValid;
  void function(ref GameApp app, ref Dwarf d, ref Job j) onClaim;
  void function(ref GameApp app, ref Dwarf d) onArrive;
  void function(ref GameApp app, ref Dwarf d) onFail;
}

Job[] jobQueue;

int[3][] activeTiles(ref GameApp app, string jobName) {
  auto matching = jobQueue.filter!(j => j.name == jobName).map!(j => j.targetTile);
  if(app.world.dwarves is null) return matching.array;
  auto dwarfMatching = app.world.dwarves.dwarves.map!(dw => dw.jobStack).joiner.filter!(j => j.name == jobName).map!(j => j.targetTile);
  return chain(matching, dwarfMatching).array;
}

/** Apply pathfinding results */
void applyPathResult(ref GameApp app, PathResult result) {
  if(app.world.dwarves is null) return;
  foreach(ref d; app.world.dwarves) {
    if(d.uid != result.dwarfUID) continue;
    if(!result.success) {
      if(d.jobStack.length > 0) {
        d.jobStack[0].failedBy[d.uid] = true;
        if(d.jobStack.length > 1) d.jobStack[$-1].failedBy[d.uid] = true;
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

/** Check if object T is adjacent to targetTile.
 * Requires T to have: tile */
bool atDestination(T)(ref GameApp app, ref T obj, int[3] targetTile, Reach reach = Reach.Adjacent) {
  final switch(reach) {
    case Reach.Adjacent: return manhattan2D(obj.tile, targetTile) == 1 && obj.tile[1] == targetTile[1];
    case Reach.OnTile: return obj.tile == targetTile;
  }
}

/** Advance progress on a task by amount; calls onComplete and completes the sub-job when progress reaches 1.0 */
void progressJob(ref GameApp app, ref Dwarf d, float amount, void delegate() onComplete) {
  d.progress += amount;
  if(d.progress >= 1.0f) { onComplete(); d.completeSubJob(); d.progress = 0.0f; }
}

/** Returns the ResourceType of a block by ID, or ResourceType.None if not found */
ResourceType blockType(ref GameApp app, uint id) { auto b = id in app.world.blocks; return b ? b.type : ResourceType.None; }

/** Claim the nearest free block of the required type for a job; sets j.targetTile to noTile if unavailable */
void claimBlock(ref GameApp app, ref Dwarf d, ref Job j) {
  if(d.carrying.any!(id => app.blockType(id) == j.tileType)) { j.state = JobState.Satisfied; return; }
  auto id = app.findFreeBlock(d.tile, j.tileType);
  if(id == noBlock) { j.state = JobState.Unavailable; return; }
  j.blockIDs = [id];
  if(auto b = id in app.world.blocks) { b.reserved = true; j.targetTile = b.tile; return; }
  j.state = JobState.Unavailable;
}

/** Claim a standable neighbour tile adjacent to j.targetTile; sets j.targetTile to noTile if none found */
void claimNeighbour(ref GameApp app, ref Job j) {
  foreach(n; app.world.tileNeighbours(j.targetTile)[0..2] ~ app.world.tileNeighbours(j.targetTile)[4..6]) {
    if(app.world.isStandable(n)) { j.targetTile = n; return; }
  }
  j.state = JobState.Unavailable;
}

/** Mining Job */
Job miningJob(int[3] targetTile) {
  return Job("Mining", targetTile, ResourceType.None, [],
    isValid: (ref GameApp app, ref Job j) => app.world.getTileAt(j.targetTile) != ResourceType.None,
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, 0.25f, () {
        ResourceType tt = app.world.getTileAt(d.jobStack[0].targetTile);
        app.setTile(d.jobStack[0].targetTile);
        app.world.pendingMineTiles ~= d.jobStack[0].targetTile;
        app.interactFeaturesAt(d.jobStack[0].targetTile.tileAbove);
        if(tt != ResourceType.None) app.spawnBlock(d.jobStack[0].targetTile, tt);
        app.world.pendingUnsettle ~= d.jobStack[0].targetTile;
      });
    },
    onFail: (ref GameApp app, ref Dwarf d) { d.failAndRequeue(); }
  );
}

/** Interact with features Job (gathering / woodcutting) */
Job interactFeatureJob(int[3] targetTile) {
  return Job("InteractFeature", targetTile, ResourceType.None, [],
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, app.getFeatureProgressRate(d.jobStack[0].targetTile), () { app.interactFeaturesAt(d.jobStack[0].targetTile); });
    },
    onFail: (ref GameApp app, ref Dwarf d) { d.failAndRequeue(); }
  );
}

/** Pickup Job */
Job pickupJob(int[3] targetTile, ResourceType tileType) {
  return Job("Fetching", targetTile, tileType, [], true,
    onClaim: (ref GameApp app, ref Dwarf d, ref Job j) { app.claimBlock(d, j); },
    onArrive: (ref GameApp app, ref Dwarf d) { app.doPickup(d); },
    onFail: (ref GameApp app, ref Dwarf d) {
      foreach(id; d.jobStack[0].blockIDs) { if(auto b = id in app.world.blocks) b.reserved = false; }
      d.failAndRequeue();
    }
  );
}

/** Job: move the dwarf to a free neighbouring tile away from their current position */
Job moveAwayJob(int[3] from) {
  return Job("MoveAway", from, ResourceType.None, [],
    onClaim: (ref GameApp app, ref Dwarf d, ref Job j) { app.claimNeighbour(j); },
    onArrive: (ref GameApp app, ref Dwarf d) { d.completeSubJob(); },
    onFail: (ref GameApp app, ref Dwarf d) { d.completeSubJob(); }
  );
}

/** Move to a free neighbouring tile and drops a carried block */
Job dropBlockJob(int[3] fromTile, uint blockID) {
  return Job("DropBlock", fromTile, ResourceType.None, [], true, [blockID],
    onClaim: (ref GameApp app, ref Dwarf d, ref Job j) { app.claimNeighbour(j); },
    onArrive: (ref GameApp app, ref Dwarf d) {
      foreach(slot, ref s; d.inventory) { if(s.isBlock && s.blockID == d.jobStack[0].blockIDs[0]) { d.drop(app, slot); break; } }
      d.completeSubJob();
    },
    onFail: (ref GameApp app, ref Dwarf d) { d.completeSubJob(); }
  );
}

/** Clean the worksite (generates a pickup job prereq) */
Job cleanWorksiteJob(int[3] targetTile) {
  return Job("CleanWorksite", targetTile, ResourceType.None, [],
    onClaim: (ref GameApp app, ref Dwarf d, ref Job j) {
      foreach(id, ref b; app.world.blocks) { if(b.tile == j.targetTile) { j.blockIDs = [id]; j.tileType = b.type; return; } }
      j.state = JobState.Satisfied;
    },
    onArrive: (ref GameApp app, ref Dwarf d) {
      if(!d.hasInventorySpace) {
        d.jobStack = [dropBlockJob(d.tile, d.carrying[0])] ~ d.jobStack;
      } else { app.doPickup(d); }
    },
    onFail: (ref GameApp app, ref Dwarf d) { d.completeSubJob(); }
  );
}

uint useCarriedBlock(ref GameApp app, ref Dwarf d, ResourceType type) {
  auto found = d.carrying.filter!(id => app.blockType(id) == type);
  if(found.empty) return noBlock;
  auto blockID = found.front;
  if(!d.use(app, blockID)) return noBlock;
  if(auto b = blockID in app.world.blocks) b.tile = builtTile;
  return blockID;
}

void evictDwarfAt(ref GameApp app, int[3] tile) {
  if(app.world.dwarves is null) return;
  foreach(ref other; app.world.dwarves.dwarves){ if(other.tile == tile) { other.jobStack = [moveAwayJob(other.tile)] ~ other.jobStack; } }
}

/** Building Job (generates a pickup job prereq) */
Job buildingJob(int[3] targetTile, ResourceType tileType) {
  return Job("Building", targetTile, tileType, [cleanWorksiteJob(targetTile), pickupJob(noTile, tileType)],
    onArrive: (ref GameApp app, ref Dwarf d) {
      if(app.isTileOccupied(d.jobStack[0].targetTile)) { app.evictDwarfAt(d.jobStack[0].targetTile); return; }
      auto blockID = app.useCarriedBlock(d, d.jobStack[0].tileType);
      if(blockID == noBlock) { d.jobStack[0].onFail(app, d); return; }
      app.setTile(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      app.world.pendingBuildTiles ~= d.jobStack[0].targetTile;
      d.completeSubJob();
    },
    onFail: (ref GameApp app, ref Dwarf d) {
      foreach(slot, ref s; d.inventory) { if(!s.empty) d.drop(app, slot); }
      auto newJob = buildingJob(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      newJob.failedBy = d.jobStack[$-1].failedBy.dup;
      newJob.failedBy[d.uid] = true;
      jobQueue ~= newJob;
      d.clearGoal();
    }
  );
}

/** Eat Job — claim nearest free Berry on the floor, walk to it, consume it */
Job eatJob() {
  return Job("Eating", noTile, ResourceType.Berry, [], true,
    onClaim: (ref GameApp app, ref Dwarf d, ref Job j) {
      auto carried = d.carrying.filter!(id => app.blockType(id) == ResourceType.Berry);
      if(!carried.empty) { j.blockIDs = [carried.front]; j.targetTile = d.tile; return; }
      auto id = app.findFreeBlock(d.tile, ResourceType.Berry);
      if(id == noBlock) { j.state = JobState.Unavailable; return; }
      if(auto b = id in app.world.blocks) { b.reserved = true; j.blockIDs = [id]; j.targetTile = b.tile; return; }
      j.state = JobState.Unavailable;
    },
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, 0.5f, () {                    // ~2 ticks to eat
        auto id = d.jobStack[0].blockIDs[0];
        if(id in app.world.blocks) app.world.blocks.remove(id);
        d.hunger = 0.0f;
        app.syncBlockInstances();
      });
    },
    onFail: (ref GameApp app, ref Dwarf d) {
      foreach(id; d.jobStack[0].blockIDs) if(auto b = id in app.world.blocks) b.reserved = false;
      d.completeSubJob();
    }
  );
}

/** Dispatch a job to a dwarf */
bool dispatchJob(ref GameApp app, ref Dwarf d, Job job) {
  d.jobStack = job.prereqs ~ [job];
  foreach(ref j; d.jobStack) { if(j.onClaim !is null) j.onClaim(app, d, j); }
  if(d.jobStack.any!(j => j.state == JobState.Unavailable)) { app.rejectJob(d, job); return false; }
  if(d.jobStack.any!(j => j.isValid !is null && !j.isValid(app, j))) { app.rejectJob(d, job); return false; }

  d.jobStack = d.jobStack.filter!(j => j.state != JobState.Satisfied).array;
  if(d.jobStack.length == 0) { d.clearGoal(); return false; }
  d.targetTile = d.jobStack[0].targetTile;
  auto reach = d.jobStack[0].reach;
  auto goal = app.findGoalTile(d, reach);
  if(goal == noTile) { app.rejectJob(d, job); return false; }
  if(goal == d.tile) { d.state = DwarfState.Working; return true; }
  app.pathfindTo(d, goal);
  return true;
}

/** Execute a block pickup for the active job; marks the block as carried and completes the sub-job */
void doPickup(ref GameApp app, ref Dwarf d) {
  auto blockID = d.jobStack[0].blockIDs.length > 0 ? d.jobStack[0].blockIDs[0] : noBlock;
  if(blockID == noBlock) { d.jobStack[0].onFail(app, d); return; }
  if(auto b = blockID in app.world.blocks) {
    if(!d.pickup(blockID, b.type)) { d.jobStack[0].onFail(app, d); return; }
    b.tile = noTile;
    d.completeSubJob();
    return;
  }
  // block not found
  if(d.jobStack.length > 1) jobQueue ~= d.jobStack[$-1];
  d.clearGoal();
}

/** Try assigning a job to the closest idle dwarf */
bool tryAssign(ref GameApp app, ref Job job) {
  if(app.world.dwarves is null) return false;
  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref d; app.world.dwarves.dwarves) {
    if((d.state != DwarfState.Idle && d.state != DwarfState.Wandering) || d.uid in job.failedBy) continue;
    float dist = manhattan(job.targetTile, d.tile);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  return bestIdx >= 0 && app.dispatchJob(app.world.dwarves.dwarves[bestIdx], job);
}

/** Reject the job and requeue */
bool rejectJob(ref GameApp app, ref Dwarf d, ref Job job) {
  job.failedBy[d.uid] = true;
  if(!job.personal) jobQueue ~= job;
  d.clearGoal();
  return false;
}

/** Fail the current job and requeue */
void failAndRequeue(ref Dwarf d) {
  d.jobStack[0].failedBy[d.uid] = true;
  if(!d.jobStack[0].personal) jobQueue ~= d.jobStack[0];
  d.clearGoal();
  d.progress = 0.0f;
}

/** Fail the current job and requeue parent */
void failAndRequeueParent(ref Dwarf d) { if(d.jobStack.length > 1) jobQueue ~= d.jobStack[$-1]; d.clearGoal(); }

/** Allow a dwarf to select their next job */
void claimNextJob(ref GameApp app, ref Dwarf d) {
  size_t dwarfCount = app.world.dwarves !is null ? app.world.dwarves.length : 0;
  jobQueue = jobQueue.filter!(j => j.failedBy.length < dwarfCount).array;
  jobQueue = jobQueue.filter!(j => j.isValid is null || j.isValid(app, j)).array;

  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref job; jobQueue) {
    if(d.uid in job.failedBy) continue;
    if(job.name == "Building" && !app.hasBlocks(job.tileType)) continue;
    float dist = manhattan(job.targetTile, d.tile);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  if(bestIdx != -1) {
    auto job = jobQueue[bestIdx];
    jobQueue = jobQueue[0..bestIdx] ~ jobQueue[bestIdx+1..$];
    app.dispatchJob(d, job);
    return;
  }

  // No job found — wander or pick up stuff
  if(++d.idleTicks[0] > d.idleTicks[1]) {
    d.idleTicks[0] = 0;
    if(app.timed!hasBlocks() && d.hasInventorySpace() && uniform(0, 2) == 0) {
      app.dispatchJob(d, pickupJob(noTile, ResourceType.None));
    } else {
      int[3] wander = [d.tile[0] + uniform(-3, 3), d.tile[1], d.tile[2] + uniform(-3, 3)];
      app.pathfindTo(d, wander);
      d.targetTile = wander;
    }
  }
}

