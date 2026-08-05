/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : resourceType, itemOf, syncBlockInstances, findFreeBlock, findFreeFood, noBlock, hasResource, release;
import color : randomColor;
import entity : tickEntity;
import inventory : deriveInventory;
import lattice : tileBelow, worldToTile, tileToWorld, chunkCoord;
import game : GameApp;
import gameobjects : Dwarves, PathMarkers;
import ghost : syncBuildGhosts;
import matrix : translate, position, scale, translateScale;
import names : randomizeName;
import pathfinding : followPath, stepMove, pathfindTo, repathTo, RepathResult, findGoalTile;
import jobs : pickupJob, requestStepAside, eatJob, fillCupJob, drinkJob, craftJob, sleepJob;
import resources : isFood, toClass, itemStack, isEmptyCup, isWaterCup;
import sfx : play;
import text : addWorldText, moveWorldText, removeWorldText;
import tile : isTileOccupied, getTileAt, surfaceAt, landingTile;
import timing : timed;
import lights : addLight, removeLight, torchLight, TORCH_HEIGHT;
import scheduler : applyPathResult, atDestination, claimNextJob, dispatchJob, pruneJobQueue, rejectJob, completeSubJob;
import vector : vAdd;
import water : findNearestWater;
import world : nextEntityUID;

enum int NEED_RETRY = 30;

struct Dwarf {
  Entity!32 entity;                         /// Shared pawn (32 inventory slots)
  alias entity this;

  Job!Dwarf[] jobStack;                     /// Job stack, [0] active, rest pending
  size_t lightIndex = size_t.max;
  size_t nameLabel = size_t.max;

  @nogc void clearGoal() nothrow { jobStack = []; targetTile = noTile; repathAttempts = 0; state = EntityState.Idle; }
  @property bool hasJob() const { return(jobStack.length > 0); }
  @property ref Job!Dwarf currentJob() { return(jobStack[0]); }

  bool tickNeeds(ref GameApp app) { return app.tryNeeds(this); }
  void whenIdle(ref GameApp app) { app.claimNextJob(this); }
  void onWork(ref GameApp app) { app.overBurdened(this); }
  void onReject(ref GameApp app, ref Job!Dwarf job) { app.rejectJob(this, job); }
  void onSubJobComplete(ref GameApp app) { app.completeSubJob(this); }
  void onBlocked(ref GameApp app) { app.handleBlocking(this); }
  void onStuck(ref GameApp app) { app.logStuck(this); }
  void onPathResult(ref GameApp app, PathResult r) { app.applyPathResult(r); }
}

/** Release job reservations, drop everything carried, retire the torch light, and remove the dwarf from the roster */
void deleteDwarf(ref GameApp app, int index) {
  if(app.world.dwarves is null || index < 0 || index >= app.world.dwarves.dwarves.length) return;

  foreach(ref j; app.world.dwarves.dwarves[index].jobStack) { app.world.drops.release(j.blockIDs); }
  foreach(id; app.world.dwarves.dwarves[index].carrying) {
    if(auto b = id in app.world.drops) { b.tile = app.world.dwarves.dwarves[index].tile; b.reserved = false; }
  }
  app.world.drops.dirty = true;

  app.removeDwarfLight(app.world.dwarves.dwarves[index]);
  app.removeDwarfNameLabel(app.world.dwarves.dwarves[index]);

  app.world.dwarves.remove(index);
  app.world.dwarves.selected = -1;
  app.world.dwarves.syncInstances();
}

/** Find a free surface tile (as in non-occupado) and on top of the world */
int[3] findFreeSurfaceTile(ref GameApp app, int startX = 0, int startZ = 0) {
  foreach(radius; 0..app.world.chunkSize) {
    for(int x = -radius; x <= radius; x++) {
      for(int z = -radius; z <= radius; z++) {
        int y = app.world.surfaceAt(startX + x, app.world.chunkHeight - 1, startZ + z);
        if(y > 0 && !app.isTileOccupied([startX + x, y + 1, startZ + z])) return [startX + x, y + 1, startZ + z];
      }
    }
  }
  return(noTile);
}

enum stepSpeed = 5.0f;    // base step rate
enum hopHeight = 2.5f;    // peak of the hop
enum nameHeight = 0.8f;   // name tag height above visualPos
enum nameScale = 0.5f;    // name tag glyph scale

/** All dwarves being framed */
void dwarfFrame(ref GameApp app, float dt) {
  if(app.world.dwarves is null) return;
  foreach(i, ref d; app.world.dwarves) {
    if(d.isFalling) continue;
    if(d.state != EntityState.Moving && d.state != EntityState.Wandering) continue;
    if(app.stepMove(d, dt, stepSpeed, hopHeight)) d.state = d.hasJob ? EntityState.Working : EntityState.Idle;
  }
  foreach(i, ref d; app.world.dwarves) {
    if(d.lightIndex != size_t.max) {
      app.lights[d.lightIndex].position = [d.visualPos[0], d.visualPos[1] + TORCH_HEIGHT, d.visualPos[2], 1.0f];
    }
    if(d.nameLabel != size_t.max) {
      app.moveWorldText(d.nameLabel, [d.visualPos[0], d.visualPos[1] + nameHeight, d.visualPos[2]]);
    }
    float sc = (app.world.chunkCoord(d.tile) in app.world.chunks) ? 1.0f : 0.0f;
    float[3] s = [sc, sc, sc];
    Matrix m = scale(Matrix.init, s);
    app.world.dwarves.instances[i] = position(m, d.visualPos);
  }
  app.world.dwarves.syncInstances();
  app.buffers["LightMatrices"].invalidate();
}

/** Rebuild path-marker instances from all dwarf paths. */
void syncPathMarkers(ref World world, bool showPaths = false) {
  if(world.paths.markers is null || world.dwarves is null) return;
  world.paths.markers.instances.reset();
  if(showPaths) {
    foreach(ref d; world.dwarves)
      foreach(l; d.path) world.paths.markers.instances ~= DrawInstance(translate([l[0], l[1] - 0.4f, l[2]]), -1, d.color);
  }
  world.paths.markers.syncInstances();
}

/** Invalidate any dwarf paths passing through the given tile and re-path them. */
void invalidatePaths(ref GameApp app, int[3] tile) {
  if(app.world.dwarves is null) return;
  foreach(ref d; app.world.dwarves.dwarves) {
    if(!d.path.any!(p => app.world.worldToTile(p) == tile)) continue;
    d.path = [];
    d.moveTo = d.moveFrom = d.visualPos;
    d.moveT = 1.0f;
    if(d.jobStack.length > 0 && d.targetTile != noTile) {
      app.repathTo(d, d.targetTile, d.jobStack[0].reach, (PathResult r){ app.applyPathResult(r); });
    }
  }
}

/** Overburdened: fumble a random item when more than half-full */
void overBurdened(ref GameApp app, ref Dwarf d, float above = 0.8f) {
  size_t filled = 0;
  foreach(ref s; d.inventory) if(!s.empty) filled++;
  if((filled > cast(size_t)(above * d.inventory.length)) && uniform(0, 100) < 2) {   // ~2%/tick over 50%
    size_t slot = uniform(0, d.inventory.length);
    d.drop(app.world.drops, slot);   // no-op if that slot is empty
    app.play("DM-CGS-03", 0.2f);
  }
}

void logStuck(ref GameApp app, ref Dwarf d) {
  static uint last = 0;
  if(app.totalFramesRendered - last < 60) return;
  last = app.totalFramesRendered;
  auto goal = app.world.findGoalTile(d.currentJob.targetTile, d.tile, d.currentJob.reach);
  SDL_Log(cstr("STUCK %s goal=%s pathLen=%d", d, goal, cast(int)d.path.length));
}

/** Dispatch the most urgent over-threshold need as a job. Returns true if one was dispatched. */
bool tryNeeds(ref GameApp app, ref Dwarf d) {
  // Hunger
  if(d.needs[Need.Hunger] >= 0.6f && d.needBackoff[Need.Hunger] == 0) {
    d.needBackoff[Need.Hunger] = max(1, NEED_RETRY / (1 + cast(int)(d.needs[Need.Hunger]*4)));
    if(d.carrying.any!(id => app.world.drops.resourceType(id).isFood)) { app.dispatchJob(d, eatJob()); return(true); }
    auto food = app.world.findFreeFood(d.tile);
    if(food != noBlock) { app.dispatchJob(d, pickupJob(noTile, app.world.drops.resourceType(food).toClass)); return(true); }
  }
  // Thirst
  if(d.needs[Need.Thirst] >= 0.6f && d.needBackoff[Need.Thirst] == 0) {
    d.needBackoff[Need.Thirst] = max(1, NEED_RETRY / (1 + cast(int)(d.needs[Need.Thirst]*4)));
    bool hasFull = d.carrying.any!(id => app.world.drops.itemOf(id).isWaterCup);
    bool hasEmpty = d.carrying.any!(id => app.world.drops.itemOf(id).isEmptyCup);
    int[3] standAt;
    bool water = app.world.findNearestWater(d.tile, standAt) != noTile;

    if(hasFull || water) {
      auto job = drinkJob!Dwarf();
      if(!hasFull) {
        if(!hasEmpty) { job.prereqs ~= craftJob("CupMaking"); } // no cup at all -> craft one
        job.prereqs ~= fillCupJob(); // fill the (crafted or carried) cup
      }
      app.dispatchJob(d, job);
      return(true);
    }
  }
  // Rest
  if(d.needs[Need.Rest] >= 0.7f && d.needBackoff[Need.Rest] == 0) {
    d.needBackoff[Need.Rest] = max(1, NEED_RETRY / (1 + cast(int)(d.needs[Need.Rest]*4u)));
    app.dispatchJob(d, sleepJob!Dwarf(d.tile)); return(true); 
  }
  return(false);
}

void handleBlocking(ref GameApp app, ref Dwarf d) {
  foreach(ref other; app.world.dwarves.dwarves) {
    if(other.uid == d.uid) continue;
    if(!app.atDestination(other, d.currentJob.targetTile, d.currentJob.reach)) continue;
    if(d.blockedSince == 0) {
      d.blockedSince = cast(uint)SDL_GetTicks();
      other.requestStepAside();
    }
    if(SDL_GetTicks() - d.blockedSince > 4000) {
      d.blockedSince = 0;
      d.state = EntityState.Idle;
      d.currentJob.onFail(app, d);
    }
    return;
  }
  d.blockedSince = 0;
  final switch(app.repathTo(d, d.currentJob.targetTile, d.currentJob.reach, (PathResult r){ app.applyPathResult(r); })) {
    case RepathResult.Unreachable: d.state = EntityState.Idle; d.currentJob.onFail(app, d); break;
    case RepathResult.AtTarget: d.state = EntityState.Working; break;
    case RepathResult.Pathing: d.state = EntityState.WaitingForPath; break;
  }
}

/** dwarfTick, ticks all dwarves in random order */
void dwarfTick(ref GameApp app) {
  if(app.world.dwarves is null) return;
  app.pruneJobQueue();
  // rebuild tickOrder when roster size changes
  if(app.world.dwarves.tickOrder.length != app.world.dwarves.length) {
    app.world.dwarves.tickOrder.length = app.world.dwarves.length;
    iota(app.world.dwarves.tickOrder.length).copy(app.world.dwarves.tickOrder[]);
  }
  app.world.dwarves.tickOrder.randomShuffle();
  foreach(i; app.world.dwarves.tickOrder) { app.tickEntity(app.world.dwarves[i]); }
  app.world.syncPathMarkers(app.showPaths);
  app.timed!syncBuildGhosts();
  app.timed!deriveInventory();
}

void ensureDwarves(ref GameApp app) {
  if(app.world.dwarves !is null) return;
  app.world.dwarves = new Dwarves();
  app.world.dwarves.onFrame = (float dt){ dwarfFrame(app, dt); };
  app.world.dwarves.onTick  = (){ dwarfTick(app); };
  app.objects ~= app.world.dwarves;
  app.world.paths.markers = new PathMarkers();
  app.objects ~= app.world.paths.markers;

  app.world.weather.clouds = new Clouds();
  app.objects ~= app.world.weather.clouds;

  app.world.water = new WaterTiles();
  app.objects ~= app.world.water;
}

void addDwarf(ref GameApp app, ref Dwarf d) {
  d.idleTicks[1] = uniform(3, 18);
  d.state = EntityState.Idle;
  auto wp = app.world.tileToWorld(d.tile);
  d.visualPos = [wp[0], wp[1] + 0.5f, wp[2]];
  d.moveFrom = d.moveTo = d.visualPos;
  d.moveT = 1.0f;
  app.world.dwarves.instances ~= DrawInstance(translate(d.visualPos), -1, d.color);
  app.addLight(torchLight(d.visualPos, d.color));
  d.lightIndex = app.lights.length - 1;
  d.nameLabel = app.addWorldText(d.firstname, d.visualPos.vAdd([0.0f, nameHeight, 0.0f]), [0.0f, 0.0f, 0.0f], nameScale, d.color, true);
  app.world.dwarves ~= d;
}

/** Spawn a Dwarf */
void spawnDwarf(ref GameApp app) {
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  app.ensureDwarves();
  Dwarf d; d.entity.data = EntityData!32(nextEntityUID++, randomColor(), tile);
  randomizeName(d);
  app.addDwarf(d);
  app.world.dwarves.syncInstances();
}

/** remove a light when a dwarf is gone */
void removeDwarfLight(ref GameApp app, ref Dwarf d) {
  if(d.lightIndex == size_t.max) return;
  auto moved = app.removeLight(d.lightIndex);
  if(moved != size_t.max) {
    foreach(ref other; app.world.dwarves.dwarves) { if(other.lightIndex == moved) { other.lightIndex = d.lightIndex; break; } }
  }
  d.lightIndex = size_t.max;
}

/** remove a dwarf's floating name tag when the dwarf is gone */
void removeDwarfNameLabel(ref GameApp app, ref Dwarf d) {
  if(d.nameLabel == size_t.max) return;
  auto moved = app.removeWorldText(d.nameLabel);
  if(moved != size_t.max) {
    foreach(ref other; app.world.dwarves.dwarves) { if(other.nameLabel == moved) { other.nameLabel = d.nameLabel; break; } }
  }
  d.nameLabel = size_t.max;
}

EntityData!32[] saveDwarfs(ref GameApp app) {
  if(app.world.dwarves is null) return [];
  return app.world.dwarves[].map!(d => d.entity.data).array;
}

void loadDwarfs(ref GameApp app, EntityData!32[] data) {
  app.ensureDwarves();
  foreach(ref dd; data) { Dwarf d; d.entity.data = dd; app.addDwarf(d); }
  app.world.dwarves.syncInstances();
  SDL_Log("loadDwarfs: %d dwarfs", cast(int)data.length);
  app.deriveInventory();
  foreach(ref d; app.world.dwarves.dwarves) if(d.uid >= nextEntityUID) nextEntityUID = d.uid + 1;
}

void settleDwarves(ref GameApp app, float dt) {
  if(app.world.dwarves is null) return;
  foreach(ref d; app.world.dwarves.dwarves) {
    if(!d.fall.isFalling) { // Lost footing by any means: start falling.
      if(d.moveT >= 1.0f && app.world.getTileAt(d.tile.tileBelow) == ResourceType.None) {
        d.fall.start(app.world, d.tile, landingTile(app.world, d.tile)); d.clearGoal();
      }
      if(!d.fall.isFalling) continue;
    }
    if(d.fall.step(dt)) {
      d.tile = d.fall.landedTile;
      d.visualPos = app.world.tileToWorld(d.tile);
      d.moveT = 1.0f;
    } else { d.visualPos[1] = d.fall.y; }
  }
}
