/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import animation : animateAsset;
import matrix : multiply, position, rotate, scale;
import pathfinding : followPath, stepMove, repathTo, RepathResult;
import resources : itemStack;
import scheduler : atDestination;
import skeleton : animateSkeleton, buildSkeleton;
import vector : vMul;

static immutable float[Need.max + 1] decay = [0.00040f, 0.00055f, 0.00018f];  /// Need decay per tick [Hunger, Thirst, Rest]
enum float WALK_RATE = 8.0f;    /// phase advance per second while moving

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

/** True while the entity is en route: following a goal path or wandering. */
@nogc bool isMoving(EntityState s) pure nothrow { return s == EntityState.Moving || s == EntityState.Wandering; }

/** Advance one pawn's interpolated step; flip to Working/Idle on arrival. */
void entityMove(Pawn)(ref GameApp app, ref Pawn pawn, float dt, float speed, float hop) {
  if(!pawn.state.isMoving) return;
  float[3] d = [pawn.moveTo[0] - pawn.moveFrom[0], 0.0f, pawn.moveTo[2] - pawn.moveFrom[2]];
  if(d[0] * d[0] + d[2] * d[2] > 1e-6f) { pawn.heading = atan2(d[0], -d[2]) * (180.0f / PI); }
  if(app.stepMove(pawn, dt, speed, hop)) {
    pawn.state = pawn.hasJob ? EntityState.Working : EntityState.Idle;
  }
}

/** The immutable "Dwarf" entity row (grammar, brushes, angles); looked up by name. */
ref immutable(RawT) entityFor(string name) {
  foreach(ref e; entityTable) { if(e.name == name) { return(e); } }
  assert(0, "no [ENTITY] named " ~ name);
}

/** World transform for a posed pawn: species scale × per-uid build variance, yaw, feet seated on the ground. */
Matrix positionPawn(Pawn)(ref Skeleton s, ref const Pawn pawn, ref immutable RawT raw) {
  float[3] sc = s.dscale.vMul(raw.scale);
  Matrix world = rotate(Matrix.init, [pawn.heading + raw.facing, 0.0f, 0.0f]).multiply(scale(sc));
  position(world, [pawn.visualPos[0], pawn.visualPos[1] - 0.5f - s.footY * sc[1] + raw.offsetY, pawn.visualPos[2]]);
  return world;
}

/** Emit one UNIT primitive instance per rig node; the GPU skins it by that node's absolute palette slot. */
void poseEntity(Container, Pawn)(ref GameApp app, Container container, ref Pawn pawn, ref immutable RawT raw, float dt) {
  app.buildSkeleton(container, pawn.uid, raw);
  app.animateSkeleton(container.skel[pawn.uid], pawn, raw, dt);
  auto s = container.skel[pawn.uid];
  Matrix world = positionPawn(s, pawn, raw);
  const int region = s.region;
  foreach(k, ref n; s.rig) {
    foreach(ref br; raw.brushes) { if(br.symbol == n.symbol) {
      float[4] col = br.tint ? pawn.color : br.color;
      auto inst = DrawInstance(world, -1, col);
      inst.meshdef[3] = region + s.boneSlot[k];
      container.meshes[br.mesh].instances ~= inst;
      break;
    } }
  }
}

/** A single dwarf being ticked */
void tickEntity(Pawn)(ref GameApp app, ref Pawn pawn) {
  foreach(n; 0 .. pawn.needs.length){ pawn.needs[n] = min(1.0f, pawn.needs[n] + decay[n]); }
  foreach(n; 0 .. pawn.needBackoff.length) { if(pawn.needBackoff[n] > 0) { pawn.needBackoff[n]--; } }
  if(pawn.isFalling) return;

  // Drop a job the moment it becomes invalid, in any state
  if(pawn.hasJob && pawn.currentJob.isValid !is null && !pawn.currentJob.isValid(app, pawn.currentJob)) {
    pawn.currentJob.onFail(app, pawn);
  }

  final switch(pawn.state) {
    case EntityState.Idle:
      if(pawn.tickNeeds(app)) break;
      pawn.whenIdle(app);
      break;
    case EntityState.WaitingForPath: break;
    case EntityState.Moving:
    case EntityState.Wandering:
      pawn.onWork(app);
      if(pawn.moveT >= 1.0f && pawn.path.length > 0) app.followPath(pawn);
      break;
    case EntityState.Working:
      if(!pawn.hasJob) { pawn.state = EntityState.Idle; break; }
      if(app.atDestination(pawn, pawn.currentJob.targetTile, pawn.currentJob.reach)) {
        pawn.blockedSince = 0;
        pawn.repathAttempts = 0;
        pawn.currentJob.onArrive(app, pawn);
      } else {
        if(!pawn.lastPathPartial && ++pawn.repathAttempts > 3) { 
          pawn.onStuck(app);
          pawn.currentJob.onFail(app, pawn);
          break;
        }
        final switch(app.repathTo(pawn, pawn.currentJob.targetTile, pawn.currentJob.reach, (PathResult r){ pawn.onPathResult(app, r); })) {
          case RepathResult.Unreachable: pawn.state = EntityState.WaitingForPath; pawn.currentJob.onFail(app, pawn); break;
          case RepathResult.AtTarget: pawn.state = EntityState.Working; break;
          case RepathResult.Pathing: pawn.state = EntityState.WaitingForPath; break;
        }
      }
      break;
    case EntityState.Blocked: pawn.onBlocked(app); break;
  }
}

