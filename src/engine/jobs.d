/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : spawnBlock, findFreeBlock;
import pathfinding : findGoalTile, pathfindTo;
import inventory : deriveInventory;
import tree : fellTree;
import world : noTile, setTile, tileAbove;

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

/** Mining Job */
Job miningJob(int[3] targetTile, uint retries = 3) {
  return Job("Mining", targetTile, TileType.None, [],
    onArrive: (ref App app, Dwarf d) {
      d.miningProgress += 0.25f;
      if(app.verbose) SDL_Log(toStringz(format("Dwarf %s mining %s %.0f%%", d.name, d.jobStack[0].targetTile, d.miningProgress * 100)));
      if(d.miningProgress >= 1.0f) {
        TileType tt = app.world.getTileAt(d.jobStack[0].targetTile);
        app.setTile(d.jobStack[0].targetTile);
        app.fellTree(d.jobStack[0].targetTile.tileAbove);
        if(tt != TileType.None) app.spawnBlock(d.jobStack[0].targetTile, tt);
        app.world.pendingUnsettle ~= d.jobStack[0].targetTile;
        d.jobStack = d.jobStack[1..$];
        d.clearGoal();
        d.miningProgress = 0.0f;
      }
    },
    onFail: (ref App app, Dwarf d) {
      auto j = d.jobStack[0];
      j.failedBy ~= d.uid;
      jobQueue ~= j;
      d.jobStack = [];
      d.clearGoal();
      d.miningProgress = 0.0f;
    },
  );
}

Job stuffJob() { return pickupJob(noTile, TileType.None); }

/** woodcutting Job */
Job woodcuttingJob(int[3] targetTile) {
  return Job("Woodcutting", targetTile, TileType.None, [],
    onArrive: (ref App app, Dwarf d) {
      d.miningProgress += 0.25f;
      if(d.miningProgress >= 1.0f) {
        app.fellTree(d.jobStack[0].targetTile);
        d.jobStack = d.jobStack[1..$];
        d.clearGoal();
        d.miningProgress = 0.0f;
      }
    },
    onFail: (ref App app, Dwarf d) {
      auto j = d.jobStack[0];
      j.failedBy ~= d.uid;
      jobQueue ~= j;
      d.jobStack = [];
      d.clearGoal();
      d.miningProgress = 0.0f;
    }
  );
}

/** Pickup Job */
Job pickupJob(int[3] targetTile, TileType tileType) {
  return Job("Fetching", targetTile, tileType, [],
    onClaim: (ref App app, Dwarf d, ref Job j) {
      j.targetTile = app.findFreeBlock(d.tile, j.tileType);
    },
    onArrive: (ref App app, Dwarf d) { app.doPickup(d); },
    onFail: (ref App app, Dwarf d) {
      /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s FAILED %s (tileType=%s)", d.name, d.jobStack[0].name, d.jobStack[0].tileType)));
      if(d.jobStack.length > 1) jobQueue ~= d.jobStack[1];
      d.jobStack = [];
      d.clearGoal();
    }
  );
}

Job holdItemJob(TileType tileType) {
  return Job("HoldItem", [int.min, 0, 0], tileType, [],
    onClaim: (ref App app, Dwarf d, ref Job j) {
      if(d.carrying.canFind(j.tileType)) {
        /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s already holds %s, skipping HoldItem", d.name, j.tileType)));
        d.jobStack = d.jobStack[1..$];  // already satisfied, remove self
      } else {
        j.targetTile = app.findFreeBlock(d.tile, j.tileType);
        /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s fetching %s from %s", d.name, j.tileType, j.targetTile)));
      }
    },
    onArrive: (ref App app, Dwarf d) {
      if(d.carrying.canFind(d.jobStack[0].tileType)) {
        /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s HoldItem satisfied for %s", d.name, d.jobStack[0].tileType)));
        d.jobStack = d.jobStack[1..$];
        d.clearGoal();
        return;
      }
      app.doPickup(d);
    },
    onFail: (ref App app, Dwarf d) {
      /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s FAILED %s (tileType=%s)", d.name, d.jobStack[0].name, d.jobStack[0].tileType)));
      if(d.jobStack.length > 1) jobQueue ~= d.jobStack[1];
      d.jobStack = [];
      d.clearGoal();
    }
  );
}

/** Building Job (generates a pickup job prereq) */
Job buildingJob(int[3] targetTile, TileType tileType) {
  return Job("Building", targetTile, tileType, [holdItemJob(tileType)],
    onArrive: (ref App app, Dwarf d) {
      if(!d.use(d.jobStack[0].tileType)) { d.jobStack[0].onFail(app, d); return; }
      app.setTile(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      app.deriveInventory();
      /*if(app.verbose)*/SDL_Log(toStringz(format("Dwarf %s built %s at %s", d.name, d.jobStack[0].tileType, d.jobStack[0].targetTile)));
      d.jobStack = d.jobStack[1..$];
      d.clearGoal();
    },
    onFail: (ref App app, Dwarf d) {
      /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s FAILED Building %s at %s, requeueing", d.name, d.jobStack[0].tileType, d.jobStack[0].targetTile)));
      foreach(i, tt; d.carrying) d.drop(app, i);
      auto newJob = buildingJob(d.jobStack[0].targetTile, d.jobStack[0].tileType);
      newJob.failedBy = d.jobStack[0].failedBy ~ [d.uid];
      jobQueue ~= newJob;
      d.jobStack = [];
      d.clearGoal();
    }
  );
}

/** Dispatch a job to a dwarf */
bool dispatchJob(ref App app, Dwarf d, ref Job job) {
  /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s claimed '%s' targeting %s", d.name, job.name, job.targetTile)));
  d.jobStack = job.prereqs ~ [job];
  foreach(ref j; d.jobStack) { if(j.onClaim !is null) j.onClaim(app, d, j); }
  if(app.verbose) SDL_Log(toStringz(format("[Job] %s stack: %s", d.name, d.jobStack.map!(j => j.name).array)));
  if(d.jobStack[0].targetTile == noTile) { d.jobStack[0].onFail(app, d); return false; }
  d.targetTile = d.jobStack[0].targetTile;
  auto goal = app.findGoalTile(d);
  if(goal == noTile || !app.pathfindTo(d, goal)) { d.jobStack[0].onFail(app, d); return false; }
  return true;
}

void doPickup(ref App app, Dwarf d) {
  auto db = app.world.blocks;
  foreach(i, tile; db.tiles) {
    if(tile != d.jobStack[0].targetTile) continue;
    auto tt = cast(TileType)db.instances[i].meshdef[0];
    /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s picking up %s at %s", d.name, tt, tile)));
    if(d.pickup(tt)) {
      db.tiles     = db.tiles[0..i] ~ db.tiles[i+1..$];
      db.instances = db.instances[0..i] ~ db.instances[i+1..$];
      db.falling   = db.falling.filter!(f => f.idx != i).array;
      foreach(ref f; db.falling) if(f.idx > i) f.idx--;
      db.buffers[INSTANCE] = false;
      app.deriveInventory();
    }
    d.jobStack = d.jobStack[1..$];
    d.clearGoal();
    return;
  }
  /*if(app.verbose)*/SDL_Log(toStringz(format("[Job] %s block gone at %s, requeueing parent", d.name, d.jobStack[0].targetTile)));
  if(d.jobStack.length > 1) jobQueue ~= d.jobStack[1];
  d.jobStack = [];
  d.clearGoal();
}

/** Try assigning a job to the closest idle dwarf */
bool tryAssign(ref App app, ref Job job) {
  Dwarf best = null;
  float bestDist = float.max;
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o;
    if(d is null || (!d.isIdle && !d.isWandering) || job.failedBy.canFind(d.uid)) continue;
    float dist = abs(job.targetTile[0] - d.tile[0]) + abs(job.targetTile[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; best = d; }
  }
  return best !is null && app.dispatchJob(best, job);
}

/** Allow a dwarf to select their next job */
void claimNextJob(ref App app, Dwarf d) {
  if(jobQueue.length == 0) return;
  size_t dwarfCount = app.objects.count!(o => cast(Dwarf)o !is null);
  jobQueue = jobQueue.filter!(j => j.failedBy.length < dwarfCount).array;
  int bestIdx = -1;
  float bestDist = float.max;
  foreach(i, ref job; jobQueue) {
    if(job.failedBy.canFind(d.uid)) continue;
    float dist = abs(job.targetTile[0] - d.tile[0]) + abs(job.targetTile[2] - d.tile[2]);
    if(dist < bestDist) { bestDist = dist; bestIdx = cast(int)i; }
  }
  if(bestIdx == -1) return;
  auto job = jobQueue[bestIdx];
  jobQueue = jobQueue[0..bestIdx] ~ jobQueue[bestIdx+1..$];
  app.dispatchJob(d, job);
}
