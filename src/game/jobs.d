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
  return(r ~ j);
}

/** All live jobs matching a name: queued + on every dwarf's stack */
const(Job!Dwarf)[] liveJobs(const World world, string name) {
  const(Job!Dwarf)[] r = jobQueue.filter!(j => j.name == name).array;
  if(world.dwarves !is null) { foreach(dw; world.dwarves.dwarves) { r ~= dw.jobStack.filter!(j => j.name == name).array; } }
  return(r);
}

const(int[3])[] activeTiles(const World world, string jobName) { return world.liveJobs(jobName).map!(j => j.targetTile).array; }

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
      d.onSubJobComplete(app);
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
      d.onSubJobComplete(app);
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
      d.onSubJobComplete(app);
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
