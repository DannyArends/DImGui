/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import serialization : readWorldData, writeWorldData;
import block : spawnBlock, syncBlockInstances, noBlock;
import world : noTile, tileBelow, isTileOccupied, WORLD_MAGIC;
import matrix : position, scale, rotate;
import vector : euclidean;
import tileatlas : tileData;
import inventory : deriveInventory;
import pathmarker : syncPathMarkers;
import pathfinding : followPath, pathfindTo, findGoalTile, atDestination, repathTo;
import jobs : Job, dispatchJob, jobQueue, miningJob, stuffJob, claimNextJob, moveAwayJob;

uint nextDwarfUID = 1;

struct DwarfData {
  uint uid = 0;
  uint colorID = 0;
  int[3] tile = [0, 0, 0];
  char[64] first;
  char[64] last;
  uint[32] inventory = noBlock;  /// block IDs, noBlock = empty slot

  @property string name() { return cast(string)first[0..first.indexOf('\0')] ~ " " ~ cast(string)last[0..last.indexOf('\0')]; }
  @property void name(string s) {
    auto parts = s.split(" ");
    first[] = '\0'; first[0..min(parts[0].length, first.length)] = parts[0][0..min(parts[0].length, first.length)];
    last[]  = '\0'; if(parts.length > 1) last[0..min(parts[1].length, last.length)] = parts[1][0..min(parts[1].length, last.length)];
  }
  @property uint[] carrying() { return inventory[].filter!(id => id != noBlock).array; }
  @property bool pickup(uint blockID) { foreach(ref slot; inventory) { if(slot == noBlock) { slot = blockID; return true; } } return false; }
  @property bool use(uint blockID) { foreach(ref slot; inventory) { if(slot == blockID) { slot = noBlock; return true; } } return false; }
  @property bool drop(ref App app, size_t slot) {
    if(slot >= inventory.length || inventory[slot] == noBlock) return false;
    foreach(ref b; app.world.blocks.blocks) { if(b.id == inventory[slot]) { b.tile = tile; break; } }
    app.syncBlockInstances();
    inventory[slot] = noBlock;
    return true;
  }
}

/** Dwarven Cylinderz */
class Dwarves : Cylinder {
  Dwarf[] dwarves;
  alias dwarves this;

  this() {
    super(0.5f, 1.0f, 6);
    initInstanced(() => "Dwarves");
  }
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

  int[3] targetTile = [int.min, 0, 0];      /// Where we are going
  float[3][] path;                          /// Path we're on
  float progress = 0.0f;                    /// Job progress
  uint[2] idleTicks = [0, 180];             /// Idle ticks and Patience / Wanderlust
  Job[] jobStack;                           /// Current job stack, jobStack[0] is active, rest are pending

  float[3] visualPos = [0.0f, 0.0f, 0.0f];  /// Current interpolated position
  float[3] moveFrom = [0.0f, 0.0f, 0.0f];   /// World pos at start of move
  float[3] moveTo = [0.0f, 0.0f, 0.0f];     /// World pos at end of move
  float moveT = 1.0f;                       /// 1.0 = arrived, 0.0 = just started

  DwarfState state = DwarfState.Idle;
  uint blockedSince = 0;                    /// Timestamp when waiting for another dwarf to move

  @property bool waitingForPath(){ return(state == DwarfState.WaitingForPath); }
  @nogc void clearGoal() nothrow { jobStack = []; targetTile = noTile; state = DwarfState.Idle; }
}

/** Random names */
string randomDwarfName() {
  string[] prefixes = ["Urist", "Iden", "Meng", "Reg", "Doren", "Ast", "Nil", "Erib", "Thob", "Cog"];
  string[] suffixes = ["ral", "dor", "zan", "kel", "tok", "mis", "bur", "ith", "gar", "lon"];
  return prefixes[uniform(0, prefixes.length)] ~ suffixes[uniform(0, suffixes.length)];
}

/** Find a free surface tile (as in non-occupado) and on top of the world */
int[3] findFreeSurfaceTile(ref App app, int startX = 0, int startZ = 0) {
  foreach(radius; 0..app.world.chunkSize) {
    for(int x = -radius; x <= radius; x++) {
      for(int z = -radius; z <= radius; z++) {
        int y = app.world.surfaceAt(startX + x, app.world.chunkHeight - 1, startZ + z);
        if(y > 0 && !app.isTileOccupied([startX + x, y + 1, startZ + z])) return [startX + x, y + 1, startZ + z];
      }
    }
  }
  return [int.min, 0, 0];
}

/** All dwarves being framed */
void dwarfFrame(ref App app, ref Geometry obj, float dt) {
  auto ds = cast(Dwarves)obj;
  if(ds is null) return;
  foreach(i, ref d; ds.dwarves) {
    if(d.state != DwarfState.Moving && d.state != DwarfState.Wandering) continue;
    if(d.moveT >= 1.0f) continue;
    float cost = max(1.0f, tileData[app.world.getTileAt(d.tile.tileBelow)].cost);
    d.moveT = min(1.0f, d.moveT + dt * 1.0f / cost);
    float t = d.moveT * d.moveT * (3.0f - 2.0f * d.moveT);
    d.visualPos = [
      d.moveFrom[0] + t * (d.moveTo[0] - d.moveFrom[0]),
      d.moveFrom[1] + t * (d.moveTo[1] - d.moveFrom[1]) + 0.5f,
      d.moveFrom[2] + t * (d.moveTo[2] - d.moveFrom[2])
    ];
    ds.instances[i] = position(ds.instances[i], d.visualPos);
    ds.markDirty();
    if(d.moveT >= 1.0f) {
      if(d.path.length > 0) {
        app.followPath(d);
      } else { d.state = (d.jobStack.length > 0) ? DwarfState.Working : DwarfState.Idle; }
    }
  }
  app.syncPathMarkers();
}

/** A single dwarf being ticked */
void tickDwarf(ref App app, ref Dwarf d) {
  final switch(d.state) {
    case DwarfState.Idle:
      app.claimNextJob(d);
      break;
    case DwarfState.WaitingForPath: break;
    case DwarfState.Moving:
    case DwarfState.Wandering:
      if(d.moveT >= 1.0f && d.path.length > 0) app.followPath(d);
      break;
    case DwarfState.Working:
      if(d.jobStack.length == 0) { d.state = DwarfState.Idle; break; }
      if(app.atDestination(d, d.jobStack[0].targetTile)) {
        d.blockedSince = 0;
        d.jobStack[0].onArrive(app, d);
      } else {
        if(app.repathTo(d, d.jobStack[0].targetTile)) {
          d.state = DwarfState.WaitingForPath;
        } else { d.jobStack[0].onFail(app, d); }
      }
      break;
    case DwarfState.Blocked: app.handleBlocking(d); break;
  }
}

void handleBlocking(ref App app, ref Dwarf d) {
  foreach(ref other; app.world.dwarves.dwarves) {
    if(other.uid == d.uid) continue;
    if(!app.atDestination(other, d.jobStack[0].targetTile)) continue;
    if(d.blockedSince == 0) {
      d.blockedSince = cast(uint)SDL_GetTicks();
      if(other.jobStack.length == 0 || other.jobStack[0].name != "MoveAway") { other.jobStack = [moveAwayJob(other.tile)] ~ other.jobStack; }
    }
    if(SDL_GetTicks() - d.blockedSince > 4000) {
      d.blockedSince = 0;
      d.state = DwarfState.Idle;
      d.jobStack[0].onFail(app, d);
    }
    return;
  }
  d.blockedSince = 0;
  if(!app.repathTo(d, d.jobStack[0].targetTile)) {
    d.state = DwarfState.Idle;
    d.jobStack[0].onFail(app, d);
  } else { d.state = DwarfState.WaitingForPath; } // No longer blocked — repath
}

/** dwarfTick, ticks all dwarves in random order */
void dwarfTick(ref App app, ref Geometry obj) {
  auto ds = cast(Dwarves)obj;
  if(ds is null) return;
  foreach(i; iota(ds.dwarves.length).array.randomShuffle()) { app.tickDwarf(ds.dwarves[i]); }
}

void ensureDwarves(ref App app) {
  if(app.world.dwarves !is null) return;
  app.world.dwarves = new Dwarves();
  app.world.dwarves.onFrame = &dwarfFrame;
  app.world.dwarves.onTick  = &dwarfTick;
  app.objects ~= app.world.dwarves;
  app.world.pathMarkers = new PathMarkers();
  app.objects ~= app.world.pathMarkers;
}

void addDwarf(ref App app, ref Dwarf d) {
  d.idleTicks[1] = uniform(30, 180);
  d.state = DwarfState.Idle;
  auto wp = app.world.tileToWorld(d.tile);
  d.visualPos = [wp[0], wp[1] + 0.5f, wp[2]];
  d.moveFrom = d.moveTo = d.visualPos;
  d.moveT = 1.0f;
  DrawInstance inst = DrawInstance([0, 0, d.colorID, 0]);
  inst = position(inst, d.visualPos);
  app.world.dwarves.instances ~= inst;
  app.world.dwarves ~= d;
}

/** Spawn a Dwarf */
void spawnDwarf(ref App app, string name) {
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  app.ensureDwarves();
  Dwarf d = Dwarf(DwarfData(nextDwarfUID++, uniform(0, cast(uint)app.colors.length), tile));
  d.name = name;
  app.addDwarf(d);
  app.world.dwarves.markDirty();
}

void saveDwarfs(ref App app) {
  if(app.world.dwarves is null) return;
  DwarfData[] data = app.world.dwarves[].map!(d => d.data).array;
  writeWorldData(app.world.dwarfsPath(), data, cast(uint)data.length);
}

bool loadDwarfs(ref App app) {
  DwarfData[] data;  uint i;
  if(!readWorldData(app.world.dwarfsPath(), data, i)) return false;
  app.ensureDwarves();
  foreach(ref dd; data) { Dwarf d; d.data = dd; app.addDwarf(d); }
  app.world.dwarves.markDirty();
  SDL_Log("loadDwarfs: %d dwarfs", cast(int)data.length);
  app.deriveInventory();
  foreach(ref d; app.world.dwarves.dwarves) if(d.uid >= nextDwarfUID) nextDwarfUID = d.uid + 1;
  return true;
}

