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

/** Advance one entity's interpolated step; flip to Working/Idle on arrival. */
void entityMove(E)(ref GameApp app, ref E entity, float dt, float speed, float hop) {
  if(!entity.state.isMoving) return;
  float[3] d = [entity.moveTo[0] - entity.moveFrom[0], 0.0f, entity.moveTo[2] - entity.moveFrom[2]];
  if(d[0] * d[0] + d[2] * d[2] > 1e-6f) { entity.heading = atan2(d[0], -d[2]) * (180.0f / PI); }
  if(app.stepMove(entity, dt, speed, hop)) {
    entity.state = entity.hasJob ? EntityState.Working : EntityState.Idle;
  }
}

/** The immutable "Dwarf" entity row (grammar, brushes, angles); looked up by name. */
ref immutable(RawT) entityFor(string name) {
  foreach(ref e; entityTable) { if(e.name == name) { return(e); } }
  assert(0, "no [ENTITY] named " ~ name);
}

/** Emit one UNIT primitive instance per rig node; the GPU skins it by that node's absolute palette slot. */
void poseEntity(E, P)(ref GameApp app, E entity, ref P d, ref immutable RawT e, float dt) {
  app.buildSkeleton(entity, d.uid, e);
  auto s = &entity.skel[d.uid];                 // pointer: mutate state & read all per-uid data via one lookup
  uint pick = 0;
  foreach(ci, ref c; e.clips) if(c.whenMoving == (d.moveT < 1.0f)) { pick = cast(uint)ci; break; }
  s.state.animation = pick;
  app.animateSkeleton(*s, dt);
  auto ds = s.dscale;
  float[3] sc = [ds[0] * e.scale, ds[1] * e.scale, ds[2] * e.scale];
  Matrix world = rotate(Matrix.init, [d.heading + e.facing, 0.0f, 0.0f]).multiply(scale(sc));
  position(world, [d.visualPos[0], d.visualPos[1] - 0.5f - s.footY * sc[1] + e.offsetY, d.visualPos[2]]);
  const int region = s.region;
  foreach(k, ref n; s.rig) {
    foreach(ref br; e.brushes) if(br.symbol == n.symbol) {
      float[4] col = br.tint ? d.color : br.color;
      auto inst = DrawInstance(world, -1, col);
      inst.meshdef[3] = region + s.boneSlot[k];
      entity.meshes[br.mesh].instances ~= inst;
      break;
    }
  }
}

/** A single dwarf being ticked */
void tickEntity(E)(ref GameApp app, ref E entity) {
  foreach(n; 0 .. entity.needs.length){ entity.needs[n] = min(1.0f, entity.needs[n] + decay[n]); }
  foreach(n; 0 .. entity.needBackoff.length) { if(entity.needBackoff[n] > 0) { entity.needBackoff[n]--; } }
  if(entity.isFalling) return;

  // Drop a job the moment it becomes invalid, in any state
  if(entity.hasJob && entity.currentJob.isValid !is null && !entity.currentJob.isValid(app, entity.currentJob)) {
    entity.currentJob.onFail(app, entity);
  }

  final switch(entity.state) {
    case EntityState.Idle:
      if(entity.tickNeeds(app)) break;
      entity.whenIdle(app);
      break;
    case EntityState.WaitingForPath: break;
    case EntityState.Moving:
    case EntityState.Wandering:
      entity.onWork(app);
      if(entity.moveT >= 1.0f && entity.path.length > 0) app.followPath(entity);
      break;
    case EntityState.Working:
      if(!entity.hasJob) { entity.state = EntityState.Idle; break; }
      if(app.atDestination(entity, entity.currentJob.targetTile, entity.currentJob.reach)) {
        entity.blockedSince = 0;
        entity.repathAttempts = 0;
        entity.currentJob.onArrive(app, entity);
      } else {
        if(!entity.lastPathPartial && ++entity.repathAttempts > 3) { 
          entity.onStuck(app);
          entity.currentJob.onFail(app, entity);
          break;
        }
        final switch(app.repathTo(entity, entity.currentJob.targetTile, entity.currentJob.reach, (PathResult r){ entity.onPathResult(app, r); })) {
          case RepathResult.Unreachable: entity.state = EntityState.WaitingForPath; entity.currentJob.onFail(app, entity); break;
          case RepathResult.AtTarget: entity.state = EntityState.Working; break;
          case RepathResult.Pathing: entity.state = EntityState.WaitingForPath; break;
        }
      }
      break;
    case EntityState.Blocked: entity.onBlocked(app); break;
  }
}

