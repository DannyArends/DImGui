/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : syncBlockInstances, findFreeBlock, noBlock, hasBlocks;
import color : randomColor;
import inventory : deriveInventory;
import game : GameApp;
import gameobjects : Dwarves, PathMarkers;
import ghost : syncBuildGhosts;
import matrix : position, scale, translateScale;
import pathmarker : syncPathMarkers;
import pathfinding : pathfindTo, repathTo;
import jobs : Job, dispatchJob, eatJob, jobQueue, claimNextJob, moveAwayJob, atDestination, blockType;
import rnjesus : randomizeName;
import serialization : readData, writeData;
import tile : tileBelow, isTileOccupied, getTileAt, surfaceAt, worldToTile, tileToWorld;
import timing : timed;
import lights : addLight, torchLight, TORCH_HEIGHT;

uint nextDwarfUID = 1;

struct InventorySlot {
  enum Kind : ubyte { Empty, Block, Stack }
  Kind kind = Kind.Empty;                           /// Resource kind
  ResourceType type = ResourceType.None;            /// Resource type
  ubyte count = 0;                                  /// number of valid ids in resourceIDs
  uint[16] resourceIDs = noBlock;                   /// block/berry ids in this slot (POD, fixed-size)

  @property bool empty() const { return kind == Kind.Empty; }
  @property bool isBlock() const { return kind == Kind.Block; }
  @property bool isStack() const { return kind == Kind.Stack; }
  bool accepts(ResourceType t) {
    if(empty) return true;
    return isStack && this.type == t && count < resourceData(t).maxStack;
  }
}

struct DwarfData {
  uint uid = 0;
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];
  int[3] tile = [0, 0, 0];
  float hunger = 0.0f;                        /// 0 = full, 1.0 = starving
  char[64] first;
  char[64] last;
  InventorySlot[32] inventory;                /// block IDs, noBlock = empty slot

  @property string name() { return cast(string)first[0..first.indexOf('\0')] ~ " " ~ cast(string)last[0..last.indexOf('\0')]; }
  @property float mood() const { return 1.0f - hunger; }   // 1 = content, 0 = miserable

@property uint[] carrying() {
    uint[] ids;
    foreach(ref s; inventory) if(!s.empty) ids ~= s.resourceIDs[0 .. s.count];
    return ids;
  }

  bool pickup(uint blockID, ResourceType type) {
    foreach(ref s; inventory) {
      if(!s.accepts(type)) continue;
      if(s.empty) { s.kind = resourceData(type).maxStack > 1 ? InventorySlot.Kind.Stack : InventorySlot.Kind.Block; s.type = type; }
      s.resourceIDs[s.count] = blockID;
      s.count++;
      return true;
    }
    return false;
  }

  bool use(ref GameApp app, uint blockID) {
    if(auto b = blockID in app.world.blocks) b.reserved = false;
    foreach(ref s; inventory) {
      if(s.empty) continue;
      auto k = s.resourceIDs[0 .. s.count].countUntil(blockID);
      if(k >= 0) {
        s.resourceIDs[k] = s.resourceIDs[s.count - 1];
        s.count--;
        if(s.count == 0) s = InventorySlot.init;
        return true;
      }
    }
    return false;
  }

  bool drop(ref GameApp app, size_t slot) {
    if(slot >= inventory.length || inventory[slot].empty) { return(false); }

    if(auto b = inventory[slot].resourceIDs[inventory[slot].count - 1] in app.world.blocks) {
      b.tile = tile;
      b.reserved = false;
    }
    inventory[slot].count--;
    if(inventory[slot].count == 0) inventory[slot] = InventorySlot.init;
    app.syncBlockInstances();
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

  size_t lightIndex = size_t.max; 

  DwarfState state = DwarfState.Idle;
  uint blockedSince = 0;                    /// Timestamp when waiting for another dwarf to move

  @nogc void clearGoal() nothrow { jobStack = []; targetTile = noTile; state = DwarfState.Idle; }
  @property bool hasJob() const { return(jobStack.length > 0); }
  @property ref Job currentJob() { return(jobStack[0]); }
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

enum stepSpeed = 5.0f;   // base step rate
enum hopHeight = 2.5f;  // peak of the hop

/** All dwarves being framed */
void dwarfFrame(ref GameApp app, float dt) {
  if(app.world.dwarves is null) return;
  foreach(i, ref d; app.world.dwarves) {
    if(d.state != DwarfState.Moving && d.state != DwarfState.Wandering) continue;
    if(d.moveT >= 1.0f) continue;
    float cost = max(1.0f, resourceData(app.world.getTileAt(d.tile.tileBelow)).cost);
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
    if(d.lightIndex != size_t.max){ app.lights[d.lightIndex].position = [d.visualPos[0], d.visualPos[1] + TORCH_HEIGHT, d.visualPos[2], 1.0f]; }
    float[3] s = (app.world.chunkCoord(d.tile) in app.world.chunks) ? [1.0f,1.0f,1.0f] : [0.0f,0.0f,0.0f];
    Matrix m = scale(Matrix.init, s);
    app.world.dwarves.instances[i] = position(m, d.visualPos);
  }
  app.world.dwarves.instances.buffered = false;
  app.buffers["LightMatrices"].dirty[] = true;
}

/** Overburdened: fumble a random item when more than half-full */
void overBurdened(ref GameApp app, ref Dwarf d, float above = 0.8f) {
  size_t filled = 0;
  foreach(ref s; d.inventory) if(!s.empty) filled++;
  if((filled > cast(size_t)(above * d.inventory.length)) && uniform(0, 100) < 2) {   // ~2%/tick over 50%
    size_t slot = uniform(0, d.inventory.length);
    d.drop(app, slot);   // no-op if that slot is empty
  }
}

/** A single dwarf being ticked */
void tickDwarf(ref GameApp app, ref Dwarf d) {
  d.hunger = min(1.0f, d.hunger + 0.00083f);
  final switch(d.state) {
    case DwarfState.Idle:
      bool haveBerry = app.findFreeBlock(d.tile, ResourceType.Berry) != noBlock || d.carrying.any!(id => app.blockType(id) == ResourceType.Berry);
      if(d.hunger >= 0.6f && haveBerry) { app.dispatchJob(d, eatJob()); break; }
      app.claimNextJob(d); break;
    case DwarfState.WaitingForPath: break;
    case DwarfState.Moving:
    case DwarfState.Wandering:
      app.overBurdened(d);
      if(d.moveT >= 1.0f && d.path.length > 0) app.followPath(d);
      break;
    case DwarfState.Working:
      if(!d.hasJob) { d.state = DwarfState.Idle; break; }
      if(d.currentJob.isValid !is null && !d.currentJob.isValid(app, d.currentJob)) { d.currentJob.onFail(app, d); break; }
      if(app.atDestination(d, d.currentJob.targetTile, d.currentJob.reach)) {
        d.blockedSince = 0;
        d.currentJob.onArrive(app, d);
      } else {
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
      if(!other.hasJob || other.currentJob.name != "MoveAway") { other.jobStack = [moveAwayJob(other.tile)] ~ other.jobStack; }
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
  foreach(i; iota(app.world.dwarves.length).array.randomShuffle()) { app.tickDwarf(app.world.dwarves[i]); }
  app.timed!syncBlockInstances();
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
  app.world.pathMarkers = new PathMarkers();
  app.objects ~= app.world.pathMarkers;
}

void addDwarf(ref GameApp app, ref Dwarf d) {
  d.idleTicks[1] = uniform(3, 18);
  d.state = DwarfState.Idle;
  auto wp = app.world.tileToWorld(d.tile);
  d.visualPos = [wp[0], wp[1] + 0.5f, wp[2]];
  d.moveFrom = d.moveTo = d.visualPos;
  d.moveT = 1.0f;
  DrawInstance inst = DrawInstance([0, 0], d.color, Matrix.init);
  inst = position(inst, d.visualPos);
  app.world.dwarves.instances ~= inst;
  // TODO: lightIndex is stable only because dwarves spawn at startup and never die. When a light is removed, all higher lightIndex values shift
  app.addLight(torchLight(d.visualPos, d.color));
  d.lightIndex = app.lights.length - 1;
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
  app.world.dwarves.instances.buffered = false;
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
  app.world.dwarves.instances.buffered = false;
  SDL_Log("loadDwarfs: %d dwarfs", cast(int)data.length);
  app.deriveInventory();
  foreach(ref d; app.world.dwarves.dwarves) if(d.uid >= nextDwarfUID) nextDwarfUID = d.uid + 1;
  return true;
}

