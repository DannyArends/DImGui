/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import geometry;
import io : readFile, writeFile;
import block : spawnBlock;
import world : noTile, tileBelow, isTileOccupied, WORLD_MAGIC;
import vector : euclidean;
import tileatlas : tileData;
import pathfinding : followPath, pathfindTo, findGoalTile, atDestination, repathTo;
import jobs : Job, jobQueue, miningJob, claimNextJob;

struct DwarfData {
  int[3] tile = [0, 0, 0];
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];
  char[64] first;
  char[64] last;
  TileType[32] inventory;

  @property string name() { return cast(string)first[0..first.indexOf('\0')] ~ " " ~ cast(string)last[0..last.indexOf('\0')]; }
  @property void name(string s) {
    auto parts = s.split(" ");
    first[] = '\0'; first[0..min(parts[0].length, first.length)] = parts[0][0..min(parts[0].length, first.length)];
    last[]  = '\0'; if(parts.length > 1) last[0..min(parts[1].length, last.length)] = parts[1][0..min(parts[1].length, last.length)];
  }
  @property TileType[] carrying() { 
    return inventory[].countUntil(TileType.None) >= 0 ? inventory[0..inventory[].countUntil(TileType.None)].dup : inventory[].dup;
  }
  @property bool pickup(TileType c) { foreach(ref slot; inventory) { if(slot == TileType.None) { slot = c; return(true); } } return(false); }
  @property bool use(TileType c) { foreach(ref slot; inventory) { if(slot == c) { slot = TileType.None; return true; } } return false; }
  @property bool drop(ref App app, size_t slot) {
    if(slot >= inventory.length || inventory[slot] == TileType.None) return false;
    app.spawnBlock(tile, inventory[slot]);
    inventory[slot] = TileType.None;
    return true;
  }
}

/** Dwarven Cylinderz  */
class Dwarf : Cylinder {
  DwarfData data;                           /// Data saved between sessions
  alias data this;

  int[3] targetTile = [int.min, 0, 0];      /// Where we are going
  float[3][] path;                          /// Path we're on
  float miningProgress = 0.0f;              /// Mining progress
  uint[2] idleTicks = [0, 18];              /// Idle ticks and Patience / Wanderlust
  Job[] jobStack;                           /// Current job stack, jobStack[0] is active, rest are pending

  float[3] visualPos = [0.0f, 0.0f, 0.0f];  /// Current interpolated position
  float[3] moveFrom = [0.0f, 0.0f, 0.0f];   /// World pos at start of move
  float[3] moveTo = [0.0f, 0.0f, 0.0f];     /// World pos at end of move
  float moveT = 1.0f;                       /// 1.0 = arrived, 0.0 = just started


  this(float radius = 0.5f, float height = 1.0f, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]) {
    super(radius, height, 6, color);
    idleTicks[1] = uniform(3, 18);
    geometry = (){ return(typeof(this).stringof); };
  }

  @property @nogc bool hasGoal() nothrow { return targetTile != noTile; }
  @property @nogc bool isIdle() nothrow { return !hasGoal && jobStack.length == 0; }
  @property @nogc bool isWandering() nothrow { return hasGoal && jobStack.length == 0; }
  @nogc void clearGoal() nothrow { targetTile = noTile; }
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

/** dwarfFrame */
void dwarfFrame(ref App app, ref Geometry obj, float dt) {
  auto d = cast(Dwarf)obj;
  if (d is null || d.moveT >= 1.0f) return;
  float cost = max(1.0f, tileData[app.world.getTileAt(d.tile.tileBelow)].cost);
  d.moveT = min(1.0f, d.moveT + dt * 2.0f / cost);
  float t = d.moveT * d.moveT * (3.0f - 2.0f * d.moveT);
  d.visualPos = [
    d.moveFrom[0] + t * (d.moveTo[0] - d.moveFrom[0]),
    d.moveFrom[1] + t * (d.moveTo[1] - d.moveFrom[1]) + 0.5f,
    d.moveFrom[2] + t * (d.moveTo[2] - d.moveFrom[2])
  ];
  d.position(d.visualPos);
  if (d.moveT >= 1.0f && d.path.length > 0) { app.followPath(d); }
}

/** dwarfTick */
void dwarfTick(ref App app, ref Geometry obj) {
  auto d = cast(Dwarf)obj;
  if(d is null) return;
  if(!d.hasGoal) {
    if(d.jobStack.length > 0) {
      if(!app.repathTo(d, d.jobStack[0].targetTile)) d.jobStack[0].onFail(app, d);
    } else {
      app.claimNextJob(d);
      if(d.isIdle && ++d.idleTicks[0] > d.idleTicks[1]) {
        d.idleTicks[0] = 0;
        int[3] wander = [d.tile[0] + uniform(-3, 3), d.tile[1], d.tile[2] + uniform(-3, 3)];
        if(app.pathfindTo(d, wander)) d.targetTile = wander;
      }
    }
  } else if(d.path.length > 0 && d.moveT >= 1.0f) {
    app.followPath(d);
  } else if(d.path.length == 0 && d.moveT >= 1.0f) {
    if(d.isWandering) { d.clearGoal(); }
    else if(app.atDestination(d, d.jobStack[0].targetTile)) d.jobStack[0].onArrive(app, d);
    else if(!app.repathTo(d, d.jobStack[0].targetTile)) d.jobStack[0].onFail(app, d);
  }
}

/** Spawn a Dwarf */
void spawnDwarf(ref App app, string name) {
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  Dwarf dwarf = new Dwarf();
  dwarf.name = name;
  dwarf.tile = tile;
  auto wp = app.world.tileToWorld(tile);
  dwarf.position([wp[0], wp[1], wp[2]]);
  dwarf.visualPos = [wp[0], wp[1] + 0.5f, wp[2]];
  dwarf.moveFrom  = dwarf.visualPos;
  dwarf.moveTo = dwarf.visualPos;
  dwarf.moveT = 1.0f;
  dwarf.data.color = [uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), 1.0f];
  dwarf.setColor(dwarf.data.color);
  dwarf.onFrame = &dwarfFrame;
  dwarf.onTick = &dwarfTick;
  app.objects ~= dwarf;
}

void saveDwarfs(ref App app) {
  DwarfData[] data;
  foreach(o; app.objects) { auto d = cast(Dwarf)o; if(d !is null) data ~= d.data; }
  uint[2] header = [WORLD_MAGIC, cast(uint)data.length];
  writeFile(app.world.dwarfsPath(), cast(char[])(cast(ubyte[])header ~ cast(ubyte[])data));
}

bool loadDwarfs(ref App app) {
  auto raw = readFile(app.world.dwarfsPath());
  if(raw.length < uint[2].sizeof) return(false);
  if((cast(uint[])raw)[0] != WORLD_MAGIC) { SDL_Log("loadDwarfs: invalid magic"); return(false); }
  auto data = cast(DwarfData[])raw[uint[2].sizeof..$].dup;
  foreach(ref dd; data) {
    Dwarf dwarf = new Dwarf();
    dwarf.data = dd;
    dwarf.setColor(dd.color);
    auto wp = app.world.tileToWorld(dd.tile);
    dwarf.visualPos = [wp[0], wp[1] + 0.5f, wp[2]];
    dwarf.position(dwarf.visualPos);
    dwarf.onTick  = &dwarfTick;
    dwarf.onFrame = &dwarfFrame;
    app.objects ~= dwarf;
  }
  SDL_Log("loadDwarfs: %d dwarfs", cast(int)data.length);
  return(true);
}
