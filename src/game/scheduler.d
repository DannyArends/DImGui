/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : findFor, noBlock, release;
import pathfinding : findGoalTile, pathfindTo;
import jobs : flatten, jobQueue, storeJob;
import lattice : tileToWorld, worldToTile;
import resources : carriedFor;
import stockpile : acceptedByHolder, findStockpileSlot, storedTileOf, withdrawBlock;
import tile : getSuccessors, tileAbove, isTileOccupied, hasStandableNeighbour;
import vector : manhattan, manhattan2D;

enum uint HAUL_COOLDOWN = 600;   /// Cooldown for unreachable blocks

/** Advance the job stack — removes the active sub-job and clears the dwarf's current goal */
void completeSubJob(ref GameApp app, ref Dwarf d) {
  d.jobStack = d.jobStack[1..$];
  d.targetTile = noTile;
  d.repathAttempts = 0;
  if(d.hasJob && d.currentJob.onClaim !is null) d.currentJob.onClaim(app, d, d.currentJob);
  d.state = d.hasJob ? EntityState.Working : EntityState.Idle;
}

/** Check if object T is adjacent to targetTile. Requires T to have: tile */
bool atDestination(T)(ref GameApp app, ref T obj, int[3] targetTile, Reach reach = Reach.Adjacent) {
  final switch(reach) {
    case Reach.Adjacent: return(manhattan2D(obj.tile, targetTile) == 1 && obj.tile[1] == targetTile[1]);
    case Reach.OnTile: return(obj.tile == targetTile);
    case Reach.AdjacentOrAbove: return(obj.tile == targetTile.tileAbove || (manhattan2D(obj.tile, targetTile) == 1 && obj.tile[1] == targetTile[1]));
    case Reach.AdjacentOrOnTile: return(obj.tile == targetTile || (manhattan2D(obj.tile, targetTile) == 1 && obj.tile[1] == targetTile[1]));
  }
}

/** Dispatch a job */
bool dispatchJob(T)(ref GameApp app, ref T d, Job!T job) {
  d.jobStack = flatten(job);
  foreach(ref j; d.jobStack) { if(j.onClaim !is null) j.onClaim(app, d, j); }
  if(d.jobStack.any!(j => j.state == JobState.Unavailable)) { d.onReject(app, job); return false; }
  if(d.jobStack.any!(j => j.isValid !is null && !j.isValid(app, j))) { d.onReject(app, job); return false; }

  d.jobStack = d.jobStack.filter!(j => j.state != JobState.Satisfied).array;
  if(!d.hasJob) { d.clearGoal(); return false; }
  d.targetTile = d.currentJob.targetTile;

  auto goal = app.world.findGoalTile(d.currentJob.targetTile, d.tile, d.currentJob.reach);
  if(goal == noTile) { d.onReject(app, job); return false; }
  if(goal == d.tile) { d.state = EntityState.Working; return true; }
  app.pathfindTo(d, goal, (PathResult r){ d.onPathResult(app, r); });
  return true;
}

/** Allow a dwarf to select their next job */
void claimNextJob(T)(ref GameApp app, ref T d) {
  int bestIdx = -1;
  float bestScore = -float.max;
  foreach(i, ref job; jobQueue) {
    if(d.uid in job.failedBy) continue;
    if(job.name == "Building" && !app.canObtainBlock(job, d)) continue;
    float s = app.scoreJob(d, job);
    if(s > bestScore) { bestScore = s; bestIdx = cast(int)i; }
  }
  if(bestIdx != -1) {
    auto job = jobQueue[bestIdx];
    jobQueue = jobQueue[0..bestIdx] ~ jobQueue[bestIdx+1..$];
    app.dispatchJob(d, job);
    return;
  }

  if(app.tryStoreInStockpile(d)) return;

  if(++d.idleTicks[0] > d.idleTicks[1]) { // No job found: wander or pick up stuff
    d.idleTicks[0] = 0;
    if(app.world.drops.length > 0 && d.hasInventorySpace() && uniform(0, 2) == 0) {
      //app.dispatchJob(d, pickupJob(noTile, Substance.None));
    } else { app.roam(d); d.state = EntityState.Wandering; }
  }
}

/** Reject the job and requeue */
bool rejectJob(ref GameApp app, ref Dwarf d, ref Job!Dwarf job) {
  foreach(ref j; d.jobStack){ app.world.drops.release(j.blockIDs); }
  job.failedBy[d.uid] = true;
  if(!job.personal) jobQueue ~= job;
  d.clearGoal();
  return false;
}

/** Try assigning a job to the closest idle dwarf */
bool tryAssign(T)(ref GameApp app, ref Job!T job) {
  if(app.world.dwarves is null) return false;
  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref d; app.world.dwarves.dwarves) {
    if((d.state != EntityState.Idle && d.state != EntityState.Wandering) || d.uid in job.failedBy) continue;
    float dist = manhattan(job.targetTile, d.tile);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  if(bestIdx < 0) { jobQueue ~= job; return true; }
  return app.dispatchJob(app.world.dwarves.dwarves[bestIdx], job);
}

/** Advance progress on a task by amount; calls onComplete and completes the sub-job when progress reaches 1.0 */
void progressJob(T)(ref GameApp app, ref T d, float amount, void delegate() onComplete) {
  float speed = d.currentJob.personal ? 1.0f : (0.5f + 0.5f * d.mood);
  d.progress += amount * speed;
  if(d.progress >= 1.0f) { onComplete(); d.onSubJobComplete(app); d.progress = 0.0f; }
}

/** Shared onFail handlers, named for what they do: release the job's block reservation (if any), then either give up quietly or retry later */
alias failComplete = completeSubJob;
void failRequeue(ref GameApp app, ref Dwarf d) { d.failAndRequeue(); }
void failReleaseComplete(ref GameApp app, ref Dwarf d) { app.world.drops.release(d.currentJob.blockIDs); d.onSubJobComplete(app); }
void failReleaseRequeue(ref GameApp app, ref Dwarf d) { app.world.drops.release(d.currentJob.blockIDs); d.failAndRequeue(); }

int[3] pathTileFor(ref World world, uint id, const Block b) { return (b.tile == storedTile) ? world.storedTileOf(id).tileAbove : b.tile; }

/** Execute a block pickup for the active job; marks the block as carried and completes the sub-job */
void doPickup(ref GameApp app, ref Dwarf d) {
  auto blockID = d.currentJob.blockIDs.length > 0 ? d.currentJob.blockIDs[0] : noBlock;
  if(blockID == noBlock) { d.currentJob.onFail(app, d); return; }
  if(auto b = blockID in app.world.drops) {
    if(!d.pickup(blockID, b.item)) { d.currentJob.onFail(app, d); return; }
    if(b.tile == storedTile) app.world.withdrawBlock(blockID);
    b.tile = noTile; b.fall = Fall.init;
    d.onSubJobComplete(app);
    return;
  }
  if(d.hasJob) jobQueue ~= d.jobStack[$-1]; // block not found, add job back
  d.clearGoal();
}

/** True if a partial path gets no closer to the job target — a dead-end commitment. */
private bool deadEndPartial(T)(ref GameApp app, ref T d, ref PathResult result) {
  if(!d.hasJob || !result.partial || result.path.length == 0) return false;
  return manhattan(app.world.worldToTile(result.path[$-1]), d.currentJob.targetTile) >= manhattan(d.tile, d.currentJob.targetTile);
}

/** Apply a completed path to the requesting dwarf (job-failure handling on failure). */
void applyPathResult(ref GameApp app, PathResult result) {
  if(app.world.dwarves is null) return;
  foreach(ref d; app.world.dwarves) {
    if(d.uid != result.uid) continue;
    if(!result.success || app.deadEndPartial(d, result)) {
      if(d.hasJob) {
        foreach(bid; d.currentJob.blockIDs) { app.world.drops.haulFailedUntil[bid] = app.totalFramesRendered + HAUL_COOLDOWN; }
        d.currentJob.failedBy[d.uid] = true;
        if(d.jobStack.length > 1) d.jobStack[$-1].failedBy[d.uid] = true;
        d.currentJob.onFail(app, d);
      }
      d.state = EntityState.Idle;
      return;
    }
    d.state = d.hasJob ? EntityState.Moving : EntityState.Wandering;
    d.path = result.path;
    d.lastPathPartial = result.partial && (result.path.length > 1);
    d.moveTo = d.moveFrom = d.visualPos;
    d.moveT = 1.0f;
    return;
  }
}

/** Fail the current job and requeue */
void failAndRequeue(ref Dwarf d) {
  d.currentJob.failedBy[d.uid] = true;
  if(!d.currentJob.personal) jobQueue ~= d.currentJob;
  d.clearGoal();
  d.progress = 0.0f;
}

/** Try storing a block into a stockpile */
bool tryStoreInStockpile(ref GameApp app, ref Dwarf d) {
  foreach(id, ref b; app.world.drops) {
    if(b.tile == noTile || b.tile == builtTile || b.reserved || b.isFalling) continue;
    if(app.world.stockpiles.acceptedByHolder(id, b.item)) continue;
    if(b.tile != storedTile && app.world.findGoalTile(b.tile, d.tile, Reach.AdjacentOrOnTile) == noTile) continue;
    if(auto until = id in app.world.drops.haulFailedUntil) {
      if(app.totalFramesRendered < *until) continue;
      app.world.drops.haulFailedUntil.remove(id);
    }
    int[3] dst;
    uint sp = app.world.findStockpileSlot(b.item, d.tile, dst);
    if(sp != 0) { app.dispatchJob(d, storeJob(id, b.tile, b.item.material, dst)); return true; }
  }
  return false;
}

/** Ambient roaming: walk up to n random valid steps from the current tile, no goal */
void roam(T)(ref GameApp app, ref T obj, int n = 5) {
  float[3] at = app.world.tileToWorld(obj.tile);
  float[3][] path;
  foreach(_; 0..n) {
    auto opts = getSuccessors(app.world.data, PathNode(position: at)).filter!(s => !app.isTileOccupied(app.world.worldToTile(s.position))).array;
    if(opts.empty) break;
    at = opts[uniform(0, opts.length)].position;
    path ~= at;
  }
  if(path.length == 0) return;
  obj.path = path;
  obj.moveFrom = obj.moveTo = obj.visualPos;
  obj.moveT = 1.0f;
}

/** True if the dwarf can obtain a block of the job's type — already carrying one, or one is free to fetch. */
bool canObtainBlock(T)(ref GameApp app, ref Job!T job, ref T d) {
  return !app.carriedFor(d, job.tileClass, job.want, job.buildType).empty || app.world.findFor(d.tile, job.tileClass, job.want, job.buildType) != noBlock;
}

/** Higher is better. Distance is a soft penalty; basePriority and need-urgency dominate. */
float scoreJob(T)(ref GameApp app, ref T d, ref Job!T job) {
  return(job.basePriority - manhattan(job.targetTile, d.tile) * 0.1f);
}

/** Prune the global queue once per tick: drop jobs every dwarf has failed, and jobs no longer valid. */
void pruneJobQueue(ref GameApp app) {
  size_t dwarfCount = app.world.dwarves !is null ? app.world.dwarves.length : 0;
  jobQueue = jobQueue.filter!(j => j.failedBy.length < dwarfCount).array;
  jobQueue = jobQueue.filter!(j => j.isValid is null || j.isValid(app, j)).array;
}
