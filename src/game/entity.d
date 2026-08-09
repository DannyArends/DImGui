/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import inventory : InventorySlot;
import pathfinding : followPath, stepMove, pathfindTo, repathTo, RepathResult, findGoalTile;
import resources : itemStack;
import scheduler : atDestination;
import ctfe : parseTokens, splitColon;
import lsystem : Rule, LSystemBrushT, TurtleConfig, TurtleBrush, buildGrammar;
import turtlegfx : interpret;
import assimp : OpenAsset;
import node : Node;
import mesh : Mesh;
import bone : synthesizeBone;
import vertex : Vertex;
import matrix : Matrix, multiply, inverse, transpose;
import std.conv : to;
import std.format : format;

static immutable float[Need.max + 1] decay = [0.00040f, 0.00055f, 0.00018f];  /// Need decay per tick [Hunger, Thirst, Rest]


/** Per-species entity template: pawn behaviour + an L-system body baked into an OpenAsset. */
struct EntityT {
  string name;                                   /// Species name, e.g. "Dwarf"
  float moveSpeed = 2.0f;                        /// Tiles per second
  float hungerDecay = 0.0f, thirstDecay = 0.0f;  /// Need growth per tick
  string diet;                                   /// Substance/type eaten (empty = none)
  float scale = 1.0f, scaleVariance = 0.0f;      /// Instance scale + per-spawn variance
  float offsetY = 0.0f;                          /// Vertical render offset to seat on the tile
  float facing = 0.0f;                           /// Yaw offset correcting the model's forward axis
  string axiom = "B";                            /// L-system start symbol(s)
  Rule[] rules;                                  /// L-system production rules (empty = axiom as-is)
  LSystemBrushT[] brushes;                        /// Symbol -> mesh brushes (entities ignore the material fields)
  float lsystemYaw = 25.0f, lsystemPitch = 25.0f, lsystemRoll = 25.0f;
  float lsystemGap = 0.2f;                       /// f translation step (no draw)
}

/** CTFE: parse [ENTITY] blocks into per-species EntityT. Entity brushes carry no substance (0). */
EntityT[] parseEntities(string raw) pure {
  EntityT[] entities; EntityT e; bool inEntity;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "ENTITY":           if(inEntity){ entities ~= e; } e = EntityT.init; e.name = p[1]; inEntity = true; break;
      case "MOVE_SPEED":       e.moveSpeed = to!float(p[1]); break;
      case "HUNGER_DECAY":     e.hungerDecay = to!float(p[1]); break;
      case "THIRST_DECAY":     e.thirstDecay = to!float(p[1]); break;
      case "DIET":             e.diet = p[1]; break;
      case "SCALE":            e.scale = to!float(p[1]); break;
      case "SCALE_VARIANCE":   e.scaleVariance = to!float(p[1]); break;
      case "OFFSET_Y":         e.offsetY = to!float(p[1]); break;
      case "FACING":           e.facing = to!float(p[1]); break;
      case "LSYSTEM_ANGLE":    e.lsystemYaw = e.lsystemPitch = e.lsystemRoll = to!float(p[1]); break;
      case "LSYSTEM_GAP":      e.lsystemGap = to!float(p[1]); break;
      case "LSYSTEM_YAW":      e.lsystemYaw   = to!float(p[1]); break;
      case "LSYSTEM_PITCH":    e.lsystemPitch = to!float(p[1]); break;
      case "LSYSTEM_ROLL":     e.lsystemRoll  = to!float(p[1]); break;
      case "AXIOM":            e.axiom = p[1]; break;
      case "BRUSH":            if(p.length >= 6){
                                 e.brushes ~= LSystemBrushT(p[1][0], p[2], 0, "", to!float(p[3]), to!float(p[4]), to!bool(p[5]), 0.0f, true, 1.0f,
                                   [p.length > 6 ? to!float(p[6]) : 0.0f, p.length > 7 ? to!float(p[7]) : 0.0f, p.length > 8 ? to!float(p[8]) : 0.0f]);
                               } break;
      case "RULE":             if(p.length >= 4){ e.rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
      default: break;
    }
  }
  if(inEntity){ entities ~= e; }
  return(entities);
}

immutable EntityT[] entityTable = parseEntities(import("data/raws/entity.txt"));

/** Bake an entity's L-system body into an OpenAsset: one bone-tagged sub-mesh per drawn brush (independently movable). */
void bakeEntity(OpenAsset dest, const EntityT et) {
  TurtleConfig cfg;
  cfg.yaw = et.lsystemYaw; cfg.pitch = et.lsystemPitch; cfg.roll = et.lsystemRoll; cfg.gap = et.lsystemGap;
  foreach(ref br; et.brushes) cfg.brush[br.symbol] = TurtleBrush(-1, br.radius, br.length, br.advance, [1.0f, 1.0f, 1.0f, 1.0f], br.offset);
  auto chars = buildGrammar(0, 1, et.axiom, et.rules);
  auto grouped = interpret(chars, cfg, [0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f, 1.0f]);

  dest.rootnode = Node(et.name, 0, Matrix());
  uint meshNo = 0;
  foreach(ref br; et.brushes) {
    if(br.symbol !in grouped) continue;
    auto prim = makePrimitive(br.mesh);
    foreach(ref inst; grouped[br.symbol]) {
      string nodeName = format("%s:%s:%u", et.name, br.symbol, meshNo);
      int bone = dest.synthesizeBone(nodeName, inst.matrix);
      auto normM = inst.matrix.inverse().transpose();
      uint start = cast(uint)dest.vertices.length;
      foreach(vi; 0 .. prim.vertices.length) {
        Vertex v = prim.vertices[vi];
        auto pp = inst.matrix.multiply([v.position[0], v.position[1], v.position[2], 1.0f]);
        auto nn = normM.multiply([v.normal[0], v.normal[1], v.normal[2], 0.0f]);
        v.position = [pp[0], pp[1], pp[2]];
        v.normal   = [nn[0], nn[1], nn[2]];
        v.bones[0] = cast(uint)bone; v.weights[0] = 1.0f;
        dest.vertices ~= v;
      }
      foreach(ii; 0 .. prim.indices.length) dest.indices ~= start + prim.indices[ii];
      dest.meshes[nodeName] = Mesh([start, cast(uint)dest.vertices.length], 0);
      dest.rootnode.children ~= Node(nodeName, 1, inst.matrix, [], [nodeName]);
      meshNo++;
    }
  }
  dest.vertices.invalidate(); dest.indices.invalidate();
}

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

/** Advance one entity's interpolated step; flip to Working/Idle on arrival. */
void entityMove(T)(ref GameApp app, ref T e, float dt, float speed, float hop) {
  if(e.state != EntityState.Moving && e.state != EntityState.Wandering) return;
  float[3] d = [e.moveTo[0] - e.moveFrom[0], 0.0f, e.moveTo[2] - e.moveFrom[2]];
  if(d[0] * d[0] + d[2] * d[2] > 1e-6f) e.heading = atan2(d[0], -d[2]) * (180.0f / PI);
  if(app.stepMove(e, dt, speed, hop)) e.state = e.hasJob ? EntityState.Working : EntityState.Idle;
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

