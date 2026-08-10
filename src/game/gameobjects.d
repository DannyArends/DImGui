/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import assimp : OpenAsset;
import lsystem : buildGrammar;
import matrix : translateScale;
import turtlegfx : interpretRig;

/** Dwarven bodies, baked from the [ENTITY:Dwarf] L-system, rendered instanced. */
class Dwarves : OpenAsset {
  Dwarf[] dwarves;
  alias dwarves this;
  int selected = -1;
  size_t[] tickOrder;
  Geometry[string] meshes;          /// shared brush geometry per mesh name (Cube/Cylinder/Sphere)
  RigNode[][uint] rigs;             /// per-dwarf rig (buildGrammar(uid) -> interpretRig), keyed by uid
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
      axiom = e.axiom; rules = e.rules.dup;
      foreach(ref br; e.brushes) {
        cfg.brush[br.symbol] = TurtleBrush(-1, br.radius, br.length, br.advance, br.color, br.offset);
        symMesh[br.symbol] = br.mesh;
      }
      break;
    }
    initInstanced(() => "Dwarves");
  }

  /** Build (once) the procedural rig for a dwarf uid: seed the grammar by uid so each dwarf differs. */
  void buildRig(uint uid) {
    if(uid in rigs) return;
    auto nodes = interpretRig(buildGrammar(cast(uint)(uid * 2654435761u), 1, axiom, rules), cfg, [0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f, 1.0f]);
    float lo = 0.0f; bool any = false;
    foreach(ref n; nodes){ float y = n.inst.matrix[13]; if(!any || y < lo){ lo = y; any = true; } }
    rigs[uid] = nodes; footY[uid] = lo;
    uint h = cast(uint)(uid * 2654435761u);
    float sy  = 0.90f + (h & 255) / 255.0f * 0.22f;          // height 0.90..1.12
    float sxz = 0.85f + ((h >> 8) & 255) / 255.0f * 0.35f;   // girth  0.85..1.20
    dscale[uid] = [sxz, sy, sxz];
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
