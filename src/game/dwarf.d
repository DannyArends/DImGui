/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : resourceType, itemOf, syncBlockInstances, findFreeBlock, findFreeFood, noBlock, hasResource, release;
import color : randomColor;
import inventory : deriveInventory;
import lattice : tileBelow, worldToTile, tileToWorld, chunkCoord;
import game : GameApp;
import gameobjects : Dwarves, PathMarkers;
import ghost : syncBuildGhosts;
import matrix : position, scale, translateScale;
import pathmarker : syncPathMarkers;
import pathfinding : pathfindTo, repathTo, findGoalTile;
import jobs : pruneJobQueue, fillCupJob, drinkJob, craftJob, pickupJob, dispatchJob, eatJob, jobQueue, claimNextJob, requestStepAside, sleepJob, atDestination;
import resources : isFood, toClass, itemStack, isEmptyCup, isWaterCup;
import rnjesus : randomizeName;
import serialization : readData, writeData;
import sfx : play;
import text : addWorldText, moveWorldText, removeWorldText;
import tile : isTileOccupied, getTileAt, surfaceAt, landingTile;
import timing : timed;
import lights : addLight, removeLight, torchLight, TORCH_HEIGHT;
import vector : vAdd;
import water : findNearestWater;

uint nextDwarfUID = 1;

struct InventorySlot {
  enum Kind : ubyte { Empty, Block, Stack }
  Kind kind = Kind.Empty;                           /// Resource kind
  Item item;                                        /// What's in the slot: (shape x material [+ contents])
  ubyte count = 0;                                  /// number of valid ids in resourceIDs
  uint[16] resourceIDs = noBlock;                   /// block/berry ids in this slot (POD, fixed-size)

  @nogc @property bool empty() const nothrow { return kind == Kind.Empty; }
  @nogc @property bool isStack() const nothrow { return kind == Kind.Stack; }
  @nogc bool accepts(Item item) const {
    if(empty) return true;
    return isStack && this.item == item && count < itemStack(item);
  }
}

static immutable float[Need.max + 1] decay = [0.00040f, 0.00055f, 0.00018f];  /// Need decay per tick [Hunger, Thirst, Rest]

struct DwarfData {
  uint uid = 0;                                 /// Unique ID
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// Dwarf color
  int[3] tile = [0, 0, 0];                      /// Current tile
  float[Need.max + 1] needs = 0.0f;             /// Needs array: 0 = satisfied, 1 = critical
  char[64] first;                               /// First name
  char[64] last;                                /// Last name
  InventorySlot[32] inventory;                  /// Inventory

  @property string firstname() { return cast(string)first[0..first.indexOf('\0')]; }
  @property string name() { return cast(string)first[0..first.indexOf('\0')] ~ " " ~ cast(string)last[0..last.indexOf('\0')]; }
  @nogc @property float hunger() const { return needs[Need.Hunger]; }
  @nogc @property void hunger(float v) { needs[Need.Hunger] = v; }
  @nogc @property float thirst() const { return needs[Need.Thirst]; }
  @nogc @property void thirst(float v) { needs[Need.Thirst] = v; }
  @nogc @property float mood() const { return 1.0f - needs[].maxElement; }
  @property uint[] carrying() const {
    uint[] ids;
    foreach(ref s; inventory) if(!s.empty) ids ~= s.resourceIDs[0 .. s.count];
    return ids;
  }

  bool pickup(uint blockID, Item item) {
    foreach(ref s; inventory) {
      if(!s.accepts(item)) continue;
      if(s.empty) { s.kind = itemStack(item) > 1 ? InventorySlot.Kind.Stack : InventorySlot.Kind.Block; s.item = item; }
      s.resourceIDs[s.count] = blockID;
      s.count++;
      return true;
    }
    return false;
  }

  bool use(ref Drops drops, uint blockID) {
    if(auto b = blockID in drops) { b.reserved = false; }
    foreach(ref s; inventory) {
      if(s.empty) continue;
      auto k = s.resourceIDs[0 .. s.count].countUntil(blockID);
      if(k >= 0) {
        s.resourceIDs[k] = s.resourceIDs[s.count - 1];
        s.count--;
        if(s.count == 0) s = InventorySlot.init;
        return(true);
      }
    }
    return(false);
  }

  @nogc void retype(uint blockID, Item item) nothrow {
    foreach(ref s; inventory) {
      if(s.empty) continue;
      if(s.resourceIDs[0 .. s.count].canFind(blockID)) { s.item = item; return; } // This only works for stacksize == 1
    }
  }

  bool drop(ref Drops drops, size_t slot) {
    if(slot >= inventory.length || inventory[slot].empty) { return(false); }

    if(auto b = inventory[slot].resourceIDs[inventory[slot].count - 1] in drops) {
      b.tile = tile;
      b.reserved = false;
    }
    inventory[slot].count--;
    if(inventory[slot].count == 0) inventory[slot] = InventorySlot.init;
    drops.dirty = true;
    return(true);
  }

  @property bool hasInventorySpace() { return inventory[].any!(s => s.empty); }
}

enum DwarfState {
  Idle,           /// no job, no goal, standing still
  Wandering,      /// no job, has targetTile, following path
  WaitingForPath, /// has job, sent path request, waiting for async result
  Moving,         /// has job, following path (moveT < 1.0f)
  Working,        /// arrived at destination, executing job action
  Blocked,        /// at destination but another dwarf is in the way
}

struct Dwarf {
  DwarfData data;                           /// Data saved between sessions
  alias data this;

  int[3] targetTile = noTile;               /// Where we are going
  float[3][] path;                          /// Path we're on
  float progress = 0.0f;                    /// Job progress
  uint[2] idleTicks = [0, 180];             /// Idle ticks and Patience / Wanderlust
  Job[] jobStack;                           /// Current job stack, jobStack[0] is active, rest are pending

  float[3] visualPos = [0.0f, 0.0f, 0.0f];  /// Current interpolated position
  float[3] moveFrom = [0.0f, 0.0f, 0.0f];   /// World pos at start of move
  float[3] moveTo = [0.0f, 0.0f, 0.0f];     /// World pos at end of move
  float moveT = 1.0f;                       /// 1.0 = arrived, 0.0 = just started

  Fall fall = { weight: 5.0f };             /// PhysX
  size_t lightIndex = size_t.max; 
  size_t nameLabel = size_t.max;

  DwarfState state = DwarfState.Idle;
  bool lastPathPartial = false;
  uint blockedSince = 0;                    /// Timestamp when waiting for another dwarf to move
  uint repathAttempts = 0;                  /// Consecutive repaths on current sub-job without arriving

  @nogc void clearGoal() nothrow { jobStack = []; targetTile = noTile; repathAttempts = 0; state = DwarfState.Idle; }
  @property bool hasJob() const { return(jobStack.length > 0); }
  @property ref Job currentJob() { return(jobStack[0]); }
  @property bool isFalling() const { return fall.isFalling; }
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

  size_t last = (app.world.dwarves.dwarves.length - 1);
  if(index != last) {
    app.world.dwarves.dwarves[index] = app.world.dwarves.dwarves[last];
    app.world.dwarves.instances[index] = app.world.dwarves.instances[last];
  }
  app.world.dwarves.dwarves.length = app.world.dwarves.instances.length = last;
  app.world.dwarves.selected = -1;
  app.world.dwarves.syncInstances();
}

/** Follow the next step in object T's path.
 * Requires T to have: tile, path, visualPos, moveFrom, moveTo, moveT */
void followPath(T)(ref GameApp app, ref T obj) {
  if(obj.path.length == 0) return;
  auto next = obj.path[0];
  obj.path = obj.path[1..$];
  obj.moveFrom = obj.visualPos;
  obj.moveTo = [next[0], next[1], next[2]];
  obj.moveT = 0.0f;
  obj.tile = app.world.worldToTile(next);
  app.camera.isDirty = true;
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
    if(d.state != DwarfState.Moving && d.state != DwarfState.Wandering) continue;
    if(d.moveT >= 1.0f) continue;
    float cost = max(1.0f, app.world.getTileAt(d.tile.tileBelow).cost);
    d.moveT = min(1.0f, d.moveT + dt * stepSpeed / cost);
    float arc = hopHeight * d.moveT * (1.0f - d.moveT); 
    d.visualPos = [
      d.moveFrom[0] + d.moveT * (d.moveTo[0] - d.moveFrom[0]),
      d.moveFrom[1] + d.moveT * (d.moveTo[1] - d.moveFrom[1]) + arc,
      d.moveFrom[2] + d.moveT * (d.moveTo[2] - d.moveFrom[2])
    ];
    if(d.moveT >= 1.0f) {
      if(d.path.length > 0) {
        app.followPath(d);
      } else { d.state = d.hasJob ? DwarfState.Working : DwarfState.Idle; }
    }
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
  SDL_Log(cstr("STUCK %s job=%s d=%s tgt=%s reach=%d goal=%s pathLen=%d",
               d.name, d.currentJob.name, d.tile, d.currentJob.targetTile, cast(int)d.currentJob.reach, goal, cast(int)d.path.length));
}

/** Dispatch the most urgent over-threshold need as a job. Returns true if one was dispatched. */
bool tryNeeds(ref GameApp app, ref Dwarf d) {
  // Hunger
  if(d.needs[Need.Hunger] >= 0.6f) {
    if(d.carrying.any!(id => app.world.drops.resourceType(id).isFood)) { app.dispatchJob(d, eatJob()); return(true); }
    auto food = app.world.findFreeFood(d.tile);
    if(food != noBlock) { app.dispatchJob(d, pickupJob(noTile, app.world.drops.resourceType(food).toClass)); return(true); }
  }
  // Thirst
  if(d.needs[Need.Thirst] >= 0.6f) {
    bool hasFull = d.carrying.any!(id => app.world.drops.itemOf(id).isWaterCup);
    bool hasEmpty = d.carrying.any!(id => app.world.drops.itemOf(id).isEmptyCup);
    int[3] standAt;
    bool water = app.world.findNearestWater(d.tile, standAt) != noTile;

    if(hasFull || water) {
      auto job = drinkJob();
      if(!hasFull) {
        if(!hasEmpty) { job.prereqs ~= craftJob("CupMaking"); } // no cup at all -> craft one
        job.prereqs ~= fillCupJob(); // fill the (crafted or carried) cup
      }
      app.dispatchJob(d, job);
      return(true);
    }
  }
  // Rest
  if(d.needs[Need.Rest] >= 0.7f) { app.dispatchJob(d, sleepJob(d.tile)); return(true); }
  return(false);
}

/** A single dwarf being ticked */
void tickDwarf(ref GameApp app, ref Dwarf d) {
  foreach(n; 0 .. d.needs.length){ d.needs[n] = min(1.0f, d.needs[n] + decay[n]); }
  if(d.isFalling) return;

  // Drop a job the moment it becomes invalid, in any state
  if(d.hasJob && d.currentJob.isValid !is null && !d.currentJob.isValid(app, d.currentJob)) { d.currentJob.onFail(app, d); }

  final switch(d.state) {
    case DwarfState.Idle:
      if(app.tryNeeds(d)) break;     // replaces the hardcoded hunger block
      app.claimNextJob(d); break;
    case DwarfState.WaitingForPath: break;
    case DwarfState.Moving:
    case DwarfState.Wandering:
      app.overBurdened(d);
      if(d.moveT >= 1.0f && d.path.length > 0) app.followPath(d);
      break;
    case DwarfState.Working:
      if(!d.hasJob) { d.state = DwarfState.Idle; break; }
      if(app.atDestination(d, d.currentJob.targetTile, d.currentJob.reach)) {
        d.blockedSince = 0; d.repathAttempts = 0; d.currentJob.onArrive(app, d);
      } else {
        if(!d.lastPathPartial && ++d.repathAttempts > 3) { app.logStuck(d); d.currentJob.onFail(app, d); break; }
        if(app.repathTo(d, d.currentJob.targetTile, d.currentJob.reach)) {
          d.state = DwarfState.WaitingForPath;
        } else { d.currentJob.onFail(app, d); }
      }
      break;
    case DwarfState.Blocked: app.handleBlocking(d); break;
  }
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
      d.state = DwarfState.Idle;
      d.currentJob.onFail(app, d);
    }
    return;
  }
  d.blockedSince = 0;
  if(!app.repathTo(d, d.currentJob.targetTile, d.currentJob.reach)) {
    d.state = DwarfState.Idle;
    d.currentJob.onFail(app, d);
  } else { d.state = DwarfState.WaitingForPath; } // No longer blocked — repath
}

/** dwarfTick, ticks all dwarves in random order */
void dwarfTick(ref GameApp app) {
  if(app.world.dwarves is null) return;
  app.pruneJobQueue();
  // Future TODO: We can optimize the loop, when using a markForRemoval strategy
  foreach(uid; app.world.dwarves.dwarves.map!(d => d.uid).array.randomShuffle()) {
    auto i = app.world.dwarves.dwarves.countUntil!(d => d.uid == uid); // Find the dwarf by resolving UID to the slot
    if(i < 0) continue;
    app.tickDwarf(app.world.dwarves.dwarves[i]);
  }
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
  d.state = DwarfState.Idle;
  auto wp = app.world.tileToWorld(d.tile);
  d.visualPos = [wp[0], wp[1] + 0.5f, wp[2]];
  d.moveFrom = d.moveTo = d.visualPos;
  d.moveT = 1.0f;
  DrawInstance inst = DrawInstance(Matrix.init, -1, d.color);
  inst = position(inst, d.visualPos);
  app.world.dwarves.instances ~= inst;
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
  Dwarf d = Dwarf(DwarfData(nextDwarfUID++, randomColor(), tile));
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

void saveDwarfs(ref GameApp app) {
  if(app.world.dwarves is null) return;
  DwarfData[] data = app.world.dwarves[].map!(d => d.data).array;
  writeData(app.world.dwarfsPath(), data, cast(uint)data.length);
}

bool loadDwarfs(ref GameApp app) {
  DwarfData[] data;  uint i;
  if(!readData(app.world.dwarfsPath(), data, i)) return false;
  app.ensureDwarves();
  foreach(ref dd; data) { Dwarf d; d.data = dd; app.addDwarf(d); }
  app.world.dwarves.syncInstances();
  SDL_Log("loadDwarfs: %d dwarfs", cast(int)data.length);
  app.deriveInventory();
  foreach(ref d; app.world.dwarves.dwarves) if(d.uid >= nextDwarfUID) nextDwarfUID = d.uid + 1;
  return true;
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
