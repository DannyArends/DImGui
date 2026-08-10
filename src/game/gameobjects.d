/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import assimp : OpenAsset;
import lsystem : buildGrammar;
import matrix : multiply, translate, rotate, position, scale, translateScale;
import turtlegfx : interpretRig, globals;

enum float WALK_RATE = 8.0f;    /// phase advance per second while moving

/** Euler swing for a brush symbol from its animation channels (side = left/right sign). */
float[3] channelEuler(const AnimChannel[] anims, char sym, float side, float phase, bool moving) {
  float[3] e = [0.0f, 0.0f, 0.0f];
  foreach(ref ch; anims) if(ch.symbol == sym && !(ch.whenMoving && !moving)){
    e[ch.axis] += ch.amp * sin(phase * ch.freq + ch.phase) * (ch.bySide ? side : 1.0f);
  }
  return e;
}

/** A rig node's local transform with euler `e` applied at its joint (segment top). */
Matrix posedLocal(ref const RigNode n, const float[3] e) {
  if(e == [0.0f, 0.0f, 0.0f]) return n.local;
  float[3] p = [n.local[12] - 0.5f*n.local[4], n.local[13] - 0.5f*n.local[5], n.local[14] - 0.5f*n.local[6]];
  return translate(p).multiply(rotate(e)).multiply(translate([-p[0], -p[1], -p[2]])).multiply(n.local);
}

/** Dwarven bodies, baked from the [ENTITY:Dwarf] L-system, rendered instanced. */
class Dwarves : OpenAsset {
  Dwarf[] dwarves;
  alias dwarves this;
  int selected = -1;
  size_t[] tickOrder;
  Geometry[string] meshes;          /// shared brush geometry per mesh name (Cube/Cylinder/Sphere)
  RigNode[][uint] rig;              /// per-dwarf turtle rig (parent-indexed, walked by globals)
  float[4][char] symColor;          /// brush symbol -> baked color
  float[3][uint] dscale;            /// per-dwarf build (girth/height), seeded by uid
  float[uint] footY;                /// per-dwarf lowest bind-pose Y, to seat feet on the ground
  TurtleConfig cfg;                 /// turtle config built from the Dwarf entity brushes
  string[char] symMesh;             /// brush symbol -> primitive mesh name
  AnimChannel[] anims;
  string axiom;                     /// Dwarf grammar axiom
  Rule[] rules;                     /// Dwarf grammar rules

  this() {
    super();
    foreach(ref e; entityTable) if(e.name == "Dwarf") {
      cfg.yaw = e.lsystemYaw; cfg.pitch = e.lsystemPitch; cfg.roll = e.lsystemRoll; cfg.gap = e.lsystemGap;
      axiom = e.axiom; rules = e.rules.dup; anims = e.anims.dup;
      foreach(ref br; e.brushes) {
        cfg.brush[br.symbol] = TurtleBrush(-1, br.radius, br.length, br.advance, br.color, br.offset);
        symMesh[br.symbol] = br.mesh;
        symColor[br.symbol] = br.color;
      }
      break;
    }
    initInstanced(() => "Dwarves");
  }

  /** Build (once) the procedural rig for a dwarf uid: seed the grammar by uid so each dwarf differs. */
  void buildRig(uint uid) {
    if(uid in rig) return;
    auto r = interpretRig(buildGrammar(cast(uint)(uid * 2654435761u), 1, axiom, rules), cfg, [0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f, 1.0f]);
    float lo = 0.0f; bool any = false;
    foreach(ref n; r) { float y = n.inst.matrix[13]; if(!any || y < lo){ lo = y; any = true; } }
    rig[uid] = r; footY[uid] = lo;
    uint h = cast(uint)(uid * 2654435761u);
    float sy  = 0.90f + (h & 255) / 255.0f * 0.22f;
    float sxz = 0.85f + ((h >> 8) & 255) / 255.0f * 0.35f;
    dscale[uid] = [sxz, sy, sxz];
  }

  /** Pose dwarf `d`'s rig this frame and emit its parts into the shared brush meshes. */
  void poseDwarf(ref Dwarf d, float dt) {
    buildRig(d.uid);
    auto sc = dscale[d.uid];
    Matrix world = rotate(Matrix.init, [d.heading + 180.0f, 0.0f, 0.0f]).multiply(scale(sc));
    position(world, [d.visualPos[0], d.visualPos[1] - 0.5f - footY[d.uid] * sc[1], d.visualPos[2]]);
    bool moving = (d.state == EntityState.Moving || d.state == EntityState.Wandering);
    d.anim.animTime += dt;
    float phase = cast(float)d.anim.animTime * WALK_RATE + (d.uid % 100);
    const r = rig[d.uid];
    auto g = globals(r, world, (size_t k) {
      float side = r[k].inst.matrix[12] < 0.0f ? 1.0f : -1.0f;
      return posedLocal(r[k], channelEuler(r[k].symbol, side, phase, moving));
    });
    foreach(k, ref n; r) {
      if(n.symbol in symMesh) { meshes[symMesh[n.symbol]].instances ~= DrawInstance(g[k], -1, symColor[n.symbol]); }
    }
  }
  mixin SwapRemove!dwarves;
}

/** Data-driven foraging animals, rendered as instanced tori */
class Animals : OpenAsset {
  Animal[] animals;
  alias animals this;
  int selected = -1;
  size_t[] tickOrder;

  this(uint type) {
    super(toStringz(modelPath(animalTable[type].mesh)), false, true);
    string key = animalTable[type].mesh;
    initInstanced(() => key);
  }
  mixin SwapRemove!animals;
}

/** Renderable cube geometry for individual blocks within a chunk, not selectable */
class Tiles : Square {
  this(ChunkData cd) {
    super();
    initInstanced(() => "Tiles", cd.tileInstances);
    isSelectable = false;
    hideInObjectsWindow = true;
  }
}

/** Spatial container for a chunk, selectable via its AABB, delegates rendering to Block */
class Chunk : Cube {
  ChunkData data;
  Geometry tiles;
  bool dirty = false;
  alias data this;

  this(ChunkData cd, immutable(WorldData) wd) {
    super();
    data = cd;
    castShadow = false;
    hideInObjectsWindow = true;
    indices = [];
    float sx = wd.chunkWorldSize;
    float sy = wd.chunkHeight * wd.tileHeight;
    float cx = data.coord[0] * sx + sx * 0.5f;
    float cz = data.coord[2] * sx + sx * 0.5f;
    float cy = sy * 0.5f + wd.yOffset;
    instances = [DrawInstance(translateScale([cx, cy, cz], [sx, sy, sx]))];
    tiles = new Tiles(cd);
    geometry = (){ return "Chunk"; };
  }
}

/** Drifting voxel clouds above the world */
class Clouds : Square {
  this() {
    super();
    initInstanced(() => "Clouds");
    isSelectable = false;
    castShadow = false;
    hideInObjectsWindow = true;
  }
}

class WaterTiles : Square {
  this() {
    super();
    initInstanced(() => "WaterTiles");
    isSelectable = false;
    castShadow = false;
    hideInObjectsWindow = true;
  }
}

struct PendingBuild {
  int[3] tile;
  ResourceType type = ResourceType.None;
}

class GhostCube : Cube {
  ResourceType type = ResourceType.None;
  ToolMode activeTool = isAndroid ? ToolMode.Info : ToolMode.Select;
  PaintState paint;
  PendingBuild[] buildSelection;   /// Tiles awaiting a block-type choice
  bool showBuildWindow = false;    /// Build-type picker open
  int[3] tile = noTile;

  this(float[2] dim) {
    super(color: [1.0f, 1.0f, 1.0f, 1.0f]);
    isSelectable = false;
    isVisible = false;
    castShadow = false;
    scale([dim[0], dim[1], dim[0]]);
    geometry = (){ return(typeof(this).stringof); };
    initInstanced(() => "BuildingGhosts");
  }
}

class PathMarkers : Cylinder {
  this() {
    super(0.1f, 0.2f, 6);
    initInstanced(() => "PathMarkers");
  }
}
