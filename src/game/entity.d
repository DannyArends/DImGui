/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import inventory : InventorySlot;
import pathfinding : followPath, stepMove, pathfindTo, repathTo, RepathResult, findGoalTile;
import resources : itemStack;
import scheduler : atDestination;

static immutable float[Need.max + 1] decay = [0.00040f, 0.00055f, 0.00018f];  /// Need decay per tick [Hunger, Thirst, Rest]

/** Serializable pawn state (POD): saved to disk via Persist.pod. N = inventory slot count. */
struct EntityData(uint N) {
  uint uid = 0;                                 /// Unique ID
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// Tint
  int[3] tile = [0, 0, 0];                      /// Current tile
  float[Need.max + 1] needs = 0.0f;             /// Needs: 0 = satisfied, 1 = critical
  char[64] first;                               /// First name
  char[64] last;                                /// Last name
  InventorySlot[N] inventory;                   /// Inventory (N slots)

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
      if(s.resourceIDs[0 .. s.count].canFind(blockID)) { s.item = item; return; }
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

/** Movement/AI state shared by all pawns. */
enum EntityState {
  Idle,           /// no goal, standing still
  Wandering,      /// roaming, following path, no job
  WaitingForPath, /// sent path request, awaiting async result
  Moving,         /// following path toward a goal
  Working,        /// arrived at destination, executing action
  Blocked,        /// at destination but blocked by another pawn
}

/** Runtime pawn: serializable data + live movement state. N = inventory slot count. */
struct Entity(uint N) {
  EntityData!N data;                        /// Data saved between sessions
  alias data this;

  int[3] targetTile = noTile;               /// Where we are going
  float[3][] path;                          /// Path we're on
  uint[2] idleTicks = [0, 180];             /// [count, patience/wanderlust]
  int[Need.max + 1] needBackoff;            /// ticks before a need may be re-attempted

  float[3] visualPos = [0.0f, 0.0f, 0.0f];  /// Interpolated position
  float[3] moveFrom = [0.0f, 0.0f, 0.0f];   /// World pos at start of move
  float[3] moveTo = [0.0f, 0.0f, 0.0f];     /// World pos at end of move
  float heading = 0.0f;                     /// Facing yaw in degrees (kept while idle)
  float moveT = 1.0f;                       /// 1.0 = arrived, 0.0 = just started

  Fall fall = { weight: 5.0f };             /// Fall state
  EntityState state = EntityState.Idle;
  bool lastPathPartial = false;
  uint blockedSince = 0;
  uint repathAttempts = 0;
  float progress = 0.0f;                    /// Current sub-job progress [0,1]

  @property bool isFalling() const { return fall.isFalling; }
}

/** A single dwarf being ticked */
void tickEntity(T)(ref GameApp app, ref T d) {
  foreach(n; 0 .. d.needs.length){ d.needs[n] = min(1.0f, d.needs[n] + decay[n]); }
  foreach(n; 0 .. d.needBackoff.length) { if(d.needBackoff[n] > 0) { d.needBackoff[n]--; } }
  if(d.isFalling) return;

  // Drop a job the moment it becomes invalid, in any state
  if(d.hasJob && d.currentJob.isValid !is null && !d.currentJob.isValid(app, d.currentJob)) { d.currentJob.onFail(app, d); }

  final switch(d.state) {
    case EntityState.Idle:
      if(d.tickNeeds(app)) break;
      d.whenIdle(app);
      break;
    case EntityState.WaitingForPath: break;
    case EntityState.Moving:
    case EntityState.Wandering:
      d.onWork(app);
      if(d.moveT >= 1.0f && d.path.length > 0) app.followPath(d);
      break;
    case EntityState.Working:
      if(!d.hasJob) { d.state = EntityState.Idle; break; }
      if(app.atDestination(d, d.currentJob.targetTile, d.currentJob.reach)) {
        d.blockedSince = 0; d.repathAttempts = 0; d.currentJob.onArrive(app, d);
      } else {
        if(!d.lastPathPartial && ++d.repathAttempts > 3) { d.onStuck(app); d.currentJob.onFail(app, d); break; }
        final switch(app.repathTo(d, d.currentJob.targetTile, d.currentJob.reach, (PathResult r){ d.onPathResult(app, r); })) {
          case RepathResult.Unreachable: d.state = EntityState.WaitingForPath; d.currentJob.onFail(app, d); break;
          case RepathResult.AtTarget:    d.state = EntityState.Working; break;
          case RepathResult.Pathing:     d.state = EntityState.WaitingForPath; break;
        }
      }
      break;
    case EntityState.Blocked: d.onBlocked(app); break;
  }
}

