/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import animation : animateAsset;
import lsystem : buildGrammar;
import pathfinding : followPath, stepMove, repathTo, RepathResult;
import resources : itemStack;
import scheduler : atDestination;
import bone : synthesizeBone;
import matrix : multiply, translate, position, inverse, rotate, transpose, halfExtent, scale;
import turtlegfx : buildClips, interpretRig, jointWorld, rigToNode, rigBones, interpretAnim;
import quaternion : toQuaternion, rotate;
import assimp : OpenAsset;
import bone : mergeBones;
import node : Node;
import mesh : updateMeshInfo;

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
void entityMove(T)(ref GameApp app, ref T e, float dt, float speed, float hop) {
  if(!e.state.isMoving) return;
  float[3] d = [e.moveTo[0] - e.moveFrom[0], 0.0f, e.moveTo[2] - e.moveFrom[2]];
  if(d[0] * d[0] + d[2] * d[2] > 1e-6f) e.heading = atan2(d[0], -d[2]) * (180.0f / PI);
  if(app.stepMove(e, dt, speed, hop)) e.state = e.hasJob ? EntityState.Working : EntityState.Idle;
}

/** The immutable "Dwarf" entity row (grammar, brushes, angles); looked up by name. */
ref immutable(EntityT) entityFor(string name) {
  foreach(ref e; entityTable) { if(e.name == name) { return(e); } }
  assert(0, "no [ENTITY] named " ~ name);
}

/** Build (once) the procedural rig for a dwarf uid: seed the grammar by uid so each dwarf differs. */
void buildRig(C)(C dw, uint uid, ref immutable EntityT e) {
  if(uid in dw.rig) return;
  TurtleConfig cfg = { yaw: e.lsystemYaw, pitch: e.lsystemPitch, roll: e.lsystemRoll, gap: e.lsystemGap };
  foreach(ref br; e.brushes) cfg.brush[br.symbol] = TurtleBrush(-1, br.radius, br.length, br.advance, br.color, br.offset);
  uint hash = cast(uint)(uid * 2654435761u);
  auto r = interpretRig(buildGrammar(hash, 1, e.axiom, e.rules), cfg, [0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f, 1.0f]);
  float lo = 0.0f; bool any = false;
  foreach(ref n; r) {
    auto m = n.inst.matrix;
    float y = m[13] - m.halfExtent[1];   // lowest vertex of the segment
    if(!any || y < lo){ lo = y; any = true; }
  }
  dw.rig[uid] = r; dw.footY[uid] = lo;
  float v = 1.0f + ((hash & 255) / 255.0f * 2.0f - 1.0f) * e.scaleVariance;
  dw.dscale[uid] = [v, v, v];
}

/** Build (once per uid) the pawn's vertexless skeleton object; stamp its palette region immediately (no frame lag). */
void buildSkeleton(C)(ref GameApp app, C dw, uint uid, ref immutable EntityT e) {
  if(uid in dw.skel) return;
  dw.buildRig(uid, e);
  const r = dw.rig[uid];
  string pfx = format("%s%u.", e.name, uid);       // unique per pawn: no cross-pawn bone-name collision
  auto s = new OpenAsset();
  s.mName = format("%s:skel:%u", e.name, uid);
  s.instancedMesh = true; s.instances = [DrawInstance()]; s.states.length = 1;
  s.rootnode = rigToNode(r, pfx);
  s.bones = rigBones(r, pfx);
  s.animations = buildClips(r, pfx, e.clips);
  app.mergeBones(s);
  int[] slot; slot.length = r.length;
  foreach(k; 0 .. r.length) slot[k] = cast(int)(app.bones[format("%s%d", pfx, k)].index - s.boneBase);
  dw.boneSlot[uid] = slot;
  dw.skel[uid] = s;
  if(s.animations.length) s.onFrame = (float dt){ app.animateAsset(s, dt); };   // only drive skeletons that have clips
  app.objects ~= s;
  app.updateMeshInfo();                            // stamp s.instances[0].meshdef[3] now so poseEntity's region is valid this frame
}

/** Emit one UNIT primitive instance per rig node; the GPU skins it by that node's absolute palette slot. */
void poseEntity(C, P)(ref GameApp app, C dw, ref P d, ref immutable EntityT e) {
  app.buildSkeleton(dw, d.uid, e);
  auto s = dw.skel[d.uid];
  uint pick = 0;
  foreach(ci, ref c; e.clips) if(c.whenMoving == (d.moveT < 1.0f)) { pick = cast(uint)ci; break; }
  s.states[0].animation = pick;
  auto ds = dw.dscale[d.uid];
  float[3] sc = [ds[0] * e.scale, ds[1] * e.scale, ds[2] * e.scale];
  Matrix world = rotate(Matrix.init, [d.heading + e.facing, 0.0f, 0.0f]).multiply(scale(sc));
  position(world, [d.visualPos[0], d.visualPos[1] - 0.5f - dw.footY[d.uid] * sc[1] + e.offsetY, d.visualPos[2]]);
  const int region = s.instances[0].meshdef[3];
  auto slot = dw.boneSlot[d.uid];
  const r = dw.rig[d.uid];
  foreach(k, ref n; r) {
    foreach(ref br; e.brushes) if(br.symbol == n.symbol) {
      float[4] col = br.tint ? d.color : br.color;
      auto inst = DrawInstance(world, -1, col);
      inst.meshdef[3] = region + slot[k];
      dw.meshes[br.mesh].instances ~= inst;
      break;
    }
  }
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

