/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : resourceType, itemOf, rawHasClass, spawnBlock, hasResource, findFreeBlock, findFreeClass, syncBlockInstances, noBlock, release;
import feature : interactFeaturesAt, getFeatureProgressRate;
import lattice : tileToWorld, tileAbove, worldToTile, tileNeighbours;
import pathfinding : pathfindTo, findGoalTile, repathTo, RepathResult;
import reactions : reactionFor;
import resources : isFood, foodValue, hasClass, toClass, toType, toItem, isEmptyCup, isWaterCup;
import sfx : play;
import stockpile : findStockpileSlot, storeBlockAt, storedTileOf, withdrawBlock, acceptedByHolder;
import tile : setTile, setWater, getWater, getTileAt, isStandable, isTileOccupied, hasStandableNeighbour, getSuccessors;
import timing : timed;
import vector : manhattan, manhattan2D;
import water : findNearestWater;

enum JobState { Pending, Satisfied, Unavailable }                     /// Job states
enum Reach { Adjacent, OnTile, AdjacentOrOnTile, AdjacentOrAbove }    /// How a job can be reached
enum Need { Hunger, Thirst, Rest }                                    /// Current needs

struct Job(T) {
  string name;
  int[3] targetTile = noTile;
  ResourceClass tileClass = ResourceClass.None;
  Job!T[] prereqs;
  bool personal = false;
  uint[] blockIDs;
  bool[uint] failedBy;
  JobState state = JobState.Pending;
  Reach reach = Reach.Adjacent;
  int basePriority = 0;

  bool function(ref GameApp app, ref Job!T j) isValid;
  void function(ref GameApp app, ref T d, ref Job!T j) onClaim;
  void function(ref GameApp app, ref T d) onArrive;
  void function(ref GameApp app, ref T d) onFail;
}

Job!Dwarf[] jobQueue;

Job!T[] flatten(T)(Job!T j) {
  Job!T[] r;
  foreach(p; j.prereqs) r ~= flatten(p);
  j.prereqs = [];
  return r ~ [j];
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

/** Shared onFail handlers, named for what they do: release the job's block reservation (if any), then either give up quietly or retry later */
alias failComplete = completeSubJob;
void failRequeue(ref GameApp app, ref Dwarf d) { d.failAndRequeue(); }
void failReleaseComplete(ref GameApp app, ref Dwarf d) { app.world.drops.release(d.currentJob.blockIDs); app.completeSubJob(d); }
void failReleaseRequeue(ref GameApp app, ref Dwarf d) { app.world.drops.release(d.currentJob.blockIDs); d.failAndRequeue(); }

/** All live jobs matching a name: queued + on every dwarf's stack */
const(Job!Dwarf)[] liveJobs(const World world, string name) {
  const(Job!Dwarf)[] r = jobQueue.filter!(j => j.name == name).array;
  if(world.dwarves !is null) { foreach(dw; world.dwarves.dwarves) { r ~= dw.jobStack.filter!(j => j.name == name).array; } }
  return(r);
}

const(int[3])[] activeTiles(const World world, string jobName) { return world.liveJobs(jobName).map!(j => j.targetTile).array; }

int[3] pathTileFor(ref World world, uint id, const Block b) { return (b.tile == storedTile) ? world.storedTileOf(id).tileAbove : b.tile; }

/** Advance the job stack — removes the active sub-job and clears the dwarf's current goal */
void completeSubJob(T)(ref GameApp app, ref T d) {
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

/** Advance progress on a task by amount; calls onComplete and completes the sub-job when progress reaches 1.0 */
void progressJob(T)(ref GameApp app, ref T d, float amount, void delegate() onComplete) {
  float speed = d.currentJob.personal ? 1.0f : (0.5f + 0.5f * d.mood);
  d.progress += amount * speed;
  if(d.progress >= 1.0f) { onComplete(); app.completeSubJob(d); d.progress = 0.0f; }
}

/** Claim the nearest free block of the required type for a job; sets j.targetTile to noTile if unavailable */
void claimBlock(ref GameApp app, ref Dwarf d, ref Job!Dwarf j) {
  if(j.blockIDs.length == 0 && j.tileClass != ResourceClass.None && d.carrying.any!(cid => app.world.drops.resourceType(cid).hasClass(j.tileClass))) {
    j.state = JobState.Satisfied; return; 
  }
  uint id = j.blockIDs.length ? j.blockIDs[0] : app.world.findFreeClass(d.tile, j.tileClass);
  auto b = (id == noBlock ? null : id in app.world.drops);
  if(b is null) { j.state = JobState.Unavailable; return; }
  bool stored = (b.tile == storedTile);
  int[3] target = app.world.pathTileFor(id, *b);
  if(target == noTile) { j.state = JobState.Unavailable; return; }
  b.reserved = true;
  j.blockIDs = [id];
  j.targetTile = target;
  j.reach = stored ? Reach.Adjacent : Reach.AdjacentOrOnTile;
}

/** Claim a standable neighbour tile adjacent to j.targetTile; sets j.targetTile to noTile if none found */
void claimNeighbour(ref GameApp app, ref Dwarf d, ref Job!Dwarf j) { 
  foreach(n; tileNeighbours(j.targetTile)[0..2] ~ tileNeighbours(j.targetTile)[4..6]) {
    if(app.world.isStandable(n)) { j.targetTile = n; return; }
  }
  j.state = JobState.Unavailable;
}

void claimSelf(ref GameApp app, ref Dwarf d, ref Job!Dwarf j) { j.targetTile = d.tile; }

/** Mining Job */
Job!Dwarf miningJob(int[3] targetTile) {
  return Job!Dwarf("Mining", targetTile, ResourceClass.None, [], reach: Reach.AdjacentOrAbove,
    isValid: (ref GameApp app, ref Job!Dwarf j){ return(app.world.getTileAt(j.targetTile) != ResourceType.None); },
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, 0.25f, () {
        ResourceType tt = app.world.getTileAt(d.currentJob.targetTile);
        app.setTile(d.currentJob.targetTile);
        app.world.chunks.mine ~= d.currentJob.targetTile;
        app.interactFeaturesAt(d.currentJob.targetTile.tileAbove);
        if(tt != ResourceType.None) app.spawnBlock(d.currentJob.targetTile, tt);
        app.world.chunks.unsettle ~= d.currentJob.targetTile;
      });
    },
    onFail: &failRequeue);
}

/** A pickup bound to one specific block id (not "any block of type") */
Job!Dwarf pinnedPickup(uint blockID, int[3] fromTile, ResourceType type) { 
  auto j = pickupJob(fromTile, type.toClass); j.blockIDs = [blockID]; return j; 
}

/** Store in stockpile */
Job!Dwarf storeJob(uint blockID, int[3] fromTile, ResourceType type, int[3] toTile) {
  return Job!Dwarf("Store", toTile, type.toClass, [pinnedPickup(blockID, fromTile, type)], blockIDs: [blockID], reach: Reach.Adjacent,
    onArrive: (ref GameApp app, ref Dwarf d) {
      /* SDL_Log(cstr("STORED %s tgt=[%d,%d,%d]", d.name, d.currentJob.targetTile[0], d.currentJob.targetTile[1], d.currentJob.targetTile[2])); */
      auto picked = d.carrying.filter!(id => app.world.drops.resourceType(id).hasClass(d.currentJob.tileClass));
      if(picked.empty) { d.currentJob.onFail(app, d); return; }
      auto blockID = picked.front;
      d.use(app.world.drops, blockID);  // remove from inventory (no builtTile)
      app.world.storeBlockAt(d.currentJob.targetTile, blockID);   // sets tile = storedTile, adds to pile
      app.completeSubJob(d);
    },
    onFail: &failReleaseComplete);
}

/** Interact with features Job (gathering / woodcutting) */
Job!Dwarf interactFeatureJob(int[3] targetTile) {
  return Job!Dwarf("InteractFeature", targetTile, ResourceClass.None, [],
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, app.getFeatureProgressRate(d.currentJob.targetTile), () { app.interactFeaturesAt(d.currentJob.targetTile); });
    },
    onFail: &failRequeue);
}

/** Pickup Job */
Job!Dwarf pickupJob(int[3] targetTile, ResourceClass cls) {
  return Job!Dwarf("Fetching", targetTile, cls, [], true, reach: Reach.Adjacent,
             onClaim: &claimBlock, onArrive: &doPickup, onFail: &failReleaseRequeue);
}

/** Job: move the dwarf to a free neighbouring tile away from their current position */
Job!Dwarf moveAwayJob(int[3] from) {
  return Job!Dwarf("MoveAway", from, ResourceClass.None, [],
             onClaim: &claimNeighbour, onArrive: &failComplete,onFail: &failComplete);
}

/** Ask `other` to step aside: prepend a MoveAway to their stack unless they're already moving aside. */
void requestStepAside(ref Dwarf other) {
  if(!other.hasJob || other.currentJob.name != "MoveAway") other.jobStack = [moveAwayJob(other.tile)] ~ other.jobStack;
}

/** Move to a free neighbouring tile and drops a carried block */
Job!Dwarf dropBlockJob(int[3] fromTile, uint blockID) {
  return Job!Dwarf("DropBlock", fromTile, ResourceClass.None, [], true, [blockID],
    onClaim: &claimNeighbour,
    onArrive: (ref GameApp app, ref Dwarf d) {
      auto target = d.currentJob.blockIDs[0];
      foreach(slot, ref s; d.inventory) {
        if(!s.empty && s.resourceIDs[0 .. s.count].canFind(target)) { d.drop(app.world.drops, slot); break; }
      }
      app.completeSubJob(d);
    },
    onFail: &failComplete);
}

/** Clean the worksite (generates a pickup job prereq) */
Job!Dwarf cleanWorksiteJob(int[3] targetTile) {
  return Job!Dwarf("CleanWorksite", targetTile, ResourceClass.None, [],
    onClaim: (ref GameApp app, ref Dwarf d, ref Job!Dwarf j) {
      foreach(id, ref b; app.world.drops) { if(b.tile == j.targetTile) { j.blockIDs = [id]; j.tileClass = b.item.material.toClass; return; } }
      j.state = JobState.Satisfied;
    },
    onArrive: (ref GameApp app, ref Dwarf d) {
      if(!d.hasInventorySpace) {
        d.jobStack = [dropBlockJob(d.tile, d.carrying[0])] ~ d.jobStack;
      } else { app.doPickup(d); }
    },
    onFail: &failComplete);
}

/** Consume a carried block of `type` (removed from inventory, marked built); returns its id, or noBlock. */
uint useCarriedBlock(ref GameApp app, ref Dwarf d, ResourceType type) {
  auto found = d.carrying.filter!(id => app.world.drops.resourceType(id) == type);
  if(found.empty) return noBlock;
  auto blockID = found.front;
  if(!d.use(app.world.drops, blockID)) return noBlock;
  if(auto b = blockID in app.world.drops) b.tile = builtTile;
  return blockID;
}

/** Destroy a carried block: remove from the dwarf's inventory and from the world. */
void consumeCarried(T)(ref GameApp app, ref T d, uint id) {
  d.use(app.world.drops, id);
  if(id in app.world.drops) { app.world.drops.registry.remove(id); }
}

/** Ask every dwarf on `tile` to step aside. Returns false if any are there but the tile is boxed in (nowhere to go). */
bool evictDwarfAt(ref GameApp app, int[3] tile) {
  if(app.world.dwarves is null) return true;
  immutable boxedIn = !app.world.hasStandableNeighbour(tile);
  bool occupied = false;
  foreach(ref other; app.world.dwarves.dwarves) {
    if(other.tile != tile) continue;
    occupied = true;
    if(!boxedIn) other.requestStepAside();
  }
  return !(occupied && boxedIn);
}

/** Building Job (generates a pickup job prereq) */
Job!Dwarf buildingJob(int[3] targetTile, ResourceType tileType) {
  return Job!Dwarf("Building", targetTile, tileType.toClass, [cleanWorksiteJob(targetTile), pickupJob(noTile, tileType.toClass)],
    isValid: (ref GameApp app, ref Job!Dwarf j){ return(app.world.getTileAt(j.targetTile) == ResourceType.None); },
    onArrive: (ref GameApp app, ref Dwarf d) {
      if(app.isTileOccupied(d.currentJob.targetTile)) {
        if(!app.evictDwarfAt(d.currentJob.targetTile)){ d.currentJob.onFail(app, d); }
        return;
      }
      auto blockID = app.useCarriedBlock(d, d.currentJob.tileClass.toType);
      if(blockID == noBlock) { d.currentJob.onFail(app, d); return; }
      app.setTile(d.currentJob.targetTile, d.currentJob.tileClass.toType);
      app.world.chunks.build ~= d.currentJob.targetTile;
      app.completeSubJob(d);
    },
    onFail: (ref GameApp app, ref Dwarf d) {
      foreach(slot, ref s; d.inventory) { if(!s.empty) d.drop(app.world.drops, slot); }
      auto newJob = buildingJob(d.currentJob.targetTile, d.currentJob.tileClass.toType);
      newJob.failedBy = d.jobStack[$-1].failedBy.dup;
      newJob.failedBy[d.uid] = true;
      jobQueue ~= newJob;
      d.clearGoal();
    }
  );
}

/** Eat Job — claim nearest free Berry on the floor, walk to it, consume it */
Job!Dwarf eatJob() {
  return Job!Dwarf("Eating", noTile, ResourceClass.None, [], true, reach: Reach.OnTile,
    onClaim: (ref GameApp app, ref Dwarf d, ref Job!Dwarf j) {
      auto carried = d.carrying.filter!(id => app.world.drops.resourceType(id).isFood);
      if(carried.empty) { j.state = JobState.Unavailable; return; }
      j.blockIDs = [carried.front];
      j.targetTile = d.tile;
    },
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, 0.5f, () {
        auto id = d.currentJob.blockIDs[0];
        float restore = foodValue(app.world.drops.resourceType(id));   // read type before removal
        app.consumeCarried(d, id);
        d.hunger = d.hunger > restore ? d.hunger - restore : 0.0f;
        app.play("DM-CGS-16", 0.4f);
        app.world.drops.dirty = true;
      });
    },
    onFail: &failComplete);
}

Job!Dwarf fillCupJob() {
  return Job!Dwarf("FillCup", noTile, ResourceClass.None, [], true, reach: Reach.Adjacent,
    onClaim: (ref GameApp app, ref Dwarf d, ref Job!Dwarf j) {
      int[3] standAt;
      int[3] cell = app.world.findNearestWater(d.tile, standAt);
      if(cell == noTile) { j.state = JobState.Unavailable; return; }
      j.targetTile = cell; // cup guaranteed by the craft prereq that runs first
    },
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, 0.25f, () {
        int[3] w = d.currentJob.targetTile;
        auto cup = d.carrying.filter!(id => app.world.drops.itemOf(id).isEmptyCup);
        if(!cup.empty && app.world.getWater(w) > 0) {
          app.world.setWater(w, cast(ubyte)(app.world.getWater(w) - 1));
          if(auto b = cup.front in app.world.drops) { b.item.contents = ResourceType.Water; b.item.amount = 1; d.retype(cup.front, b.item); }
        }
        app.world.drops.dirty = true;
      });
    },
    onFail: &failComplete);
}

Job!Dwarf drinkJob() {
  return Job!Dwarf("Drinking", noTile, ResourceClass.None, [], true, reach: Reach.OnTile,
    onClaim: &claimSelf,
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, 0.5f, () {
        auto full = d.carrying.filter!(id => app.world.drops.itemOf(id).isWaterCup);
        if(!full.empty) {
          if(auto b = full.front in app.world.drops) { b.item.contents = ResourceType.None; b.item.amount = 0; d.retype(full.front, b.item); }
          d.thirst = 0.0f;
          app.play("DM-CGS-16", 0.4f);
          app.world.drops.dirty = true;
        }
      });
    },
    onFail: &failComplete);
}

Job!Dwarf craftJob(string name) {
  auto r = reactionFor(name);
  Job!Dwarf[] prereqs;
  foreach(ing; r.inputs){ foreach(n; 0 .. ing.count) {
    prereqs ~= pickupJob(noTile, cast(ResourceClass)ing.cls);
  } }
  return Job!Dwarf(name, noTile, ResourceClass.None, prereqs, true, reach: Reach.OnTile,
    onClaim: &claimSelf,
    onArrive: (ref GameApp app, ref Dwarf d) {
      auto rr = reactionFor(d.currentJob.name);
      app.progressJob(d, rr.progressRate, () {
        ResourceType[ubyte] srcMat;                          // consumed input class -> its material, for item inheritance
        foreach(ing; rr.inputs) foreach(n; 0 .. ing.count) {
          ResourceClass need = cast(ResourceClass)ing.cls;
          auto found = d.carrying.filter!(cid => app.world.drops.rawHasClass(cid, need));
          if(found.empty) continue;
          srcMat[ing.cls] = app.world.drops.resourceType(found.front);
          app.consumeCarried(d, found.front);
        }
        foreach(prod; rr.outputs) { foreach(n; 0 .. prod.count) {
          Item it = (prod.shape == cast(ubyte)ItemTemplate.None)
                  ? (cast(ResourceType)prod.type).toItem
                  : Item(cast(ItemTemplate)prod.shape, srcMat.get(prod.materialFrom, ResourceType.None));
          auto pid = app.spawnBlock(d.tile, it);
          if(d.pickup(pid, it)) {
            if(auto nb = pid in app.world.drops) { nb.tile = noTile; nb.fall = Fall.init; }
          }
        } }
        app.world.drops.dirty = true;
      });
    },
    onFail: &failReleaseRequeue);
}
Job!Dwarf sleepJob(int[3] atTile) {
  return Job!Dwarf("Sleeping", atTile, ResourceClass.None, [], true, reach: Reach.OnTile,
    basePriority: 100,
    onClaim: &claimSelf,
    onArrive: (ref GameApp app, ref Dwarf d) {
      app.progressJob(d, 0.01f, () { d.needs[Need.Rest] = 0.0f; });   // ~100 ticks of standing still
    },
    onFail: &failComplete);
}

/** Dispatch a job to a dwarf */
bool dispatchJob(T)(ref GameApp app, ref T d, Job!T job) {
  d.jobStack = flatten(job);
  foreach(ref j; d.jobStack) { if(j.onClaim !is null) j.onClaim(app, d, j); }
  if(d.jobStack.any!(j => j.state == JobState.Unavailable)) { app.rejectJob(d, job); return false; }
  if(d.jobStack.any!(j => j.isValid !is null && !j.isValid(app, j))) { app.rejectJob(d, job); return false; }

  d.jobStack = d.jobStack.filter!(j => j.state != JobState.Satisfied).array;
  if(!d.hasJob) { d.clearGoal(); return false; }
  d.targetTile = d.currentJob.targetTile;

  auto goal = app.world.findGoalTile(d.currentJob.targetTile, d.tile, d.currentJob.reach);
  if(goal == noTile) { app.rejectJob(d, job); return false; }
  if(goal == d.tile) { d.state = EntityState.Working; return true; }
  app.pathfindTo(d, goal, (PathResult r){ app.applyPathResult(r); });
  return true;
}

/** Execute a block pickup for the active job; marks the block as carried and completes the sub-job */
void doPickup(ref GameApp app, ref Dwarf d) {
  auto blockID = d.currentJob.blockIDs.length > 0 ? d.currentJob.blockIDs[0] : noBlock;
  if(blockID == noBlock) { d.currentJob.onFail(app, d); return; }
  if(auto b = blockID in app.world.drops) {
    if(!d.pickup(blockID, b.item)) { d.currentJob.onFail(app, d); return; }
    if(b.tile == storedTile) app.world.withdrawBlock(blockID);
    b.tile = noTile;
    b.fall = Fall.init;
    app.completeSubJob(d);
    return;
  }
  if(d.hasJob) jobQueue ~= d.jobStack[$-1]; // block not found, add job back
  d.clearGoal();
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

/** Reject the job and requeue */
bool rejectJob(T)(ref GameApp app, ref Dwarf d, ref Job!T job) {
  foreach(ref j; d.jobStack){ app.world.drops.release(j.blockIDs); }
  job.failedBy[d.uid] = true;
  if(!job.personal) jobQueue ~= job;
  d.clearGoal();
  return false;
}

/** Fail the current job and requeue */
void failAndRequeue(ref Dwarf d) {
  d.currentJob.failedBy[d.uid] = true;
  if(!d.currentJob.personal) jobQueue ~= d.currentJob;
  d.clearGoal();
  d.progress = 0.0f;
}

/** Try storing a block inot a stockpile */
bool tryStoreInStockpile(ref GameApp app, ref Dwarf d) {
  foreach(id, ref b; app.world.drops) {
    if(b.tile == noTile || b.tile == builtTile || b.reserved || b.isFalling) continue;
    if(app.world.stockpiles.acceptedByHolder(id, b.item)) continue;
    if(!(b.tile == storedTile) && !app.world.hasStandableNeighbour(b.tile)) continue;
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

/** Higher is better. Distance is a soft penalty; basePriority and need-urgency dominate. */
float scoreJob(T)(ref GameApp app, ref T d, ref Job!T job) {
  float dist = manhattan(job.targetTile, d.tile);
  return job.basePriority - dist * 0.1f;
}

/** True if the dwarf can obtain a block of the job's type — already carrying one, or one is free to fetch. */
bool canObtainBlock(T)(ref GameApp app, ref Job!T job, ref T d){
  return d.carrying.any!(cid => app.world.drops.resourceType(cid).hasClass(job.tileClass)) || app.world.findFreeClass(d.tile, job.tileClass) != noBlock;
}

/** Prune the global queue once per tick: drop jobs every dwarf has failed, and jobs no longer valid. */
void pruneJobQueue(ref GameApp app) {
  size_t dwarfCount = app.world.dwarves !is null ? app.world.dwarves.length : 0;
  jobQueue = jobQueue.filter!(j => j.failedBy.length < dwarfCount).array;
  jobQueue = jobQueue.filter!(j => j.isValid is null || j.isValid(app, j)).array;
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

  // No job found — wander or pick up stuff
  if(++d.idleTicks[0] > d.idleTicks[1]) {
    d.idleTicks[0] = 0;
    if(app.world.drops.length > 0 && d.hasInventorySpace() && uniform(0, 2) == 0) {
      //app.dispatchJob(d, pickupJob(noTile, ResourceClass.None));
    } else { app.roam(d); d.state = EntityState.Wandering; }
  }
}

