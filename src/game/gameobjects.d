/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import assimp : OpenAsset;
import entitytype : EntityT;
import geometry : addVertex;
import lsystem : TurtleConfig, TurtleBrush, buildGrammar;
import matrix : translateScale, multiply;
import turtlegfx : interpret;
import vertex : Vertex;
import vector : midpoint;

/** Bake an entity's L-system body into an OpenAsset's buffers: merge each brush's primitive,
 *  transformed by its interpreted instance matrix. Rigid for now; per-dwarf transform/colour drive it. */
void bakeEntity(OpenAsset dest, const EntityT et) {
  TurtleConfig cfg;
  cfg.yaw = et.lsystemYaw; cfg.pitch = et.lsystemPitch; cfg.roll = et.lsystemRoll;
  foreach(ref br; et.brushes) cfg.brush[br.symbol] = TurtleBrush(-1, br.radius, br.length, br.advance, [1.0f, 1.0f, 1.0f, 1.0f]);
  auto chars = buildGrammar(0, 1, et.axiom, et.rules);
  auto grouped = interpret(chars, cfg, [0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f, 1.0f]);
  foreach(ref br; et.brushes) {
    if(br.symbol !in grouped) continue;
    auto prim = makePrimitive(br.mesh);
    foreach(ref inst; grouped[br.symbol]) {
      uint base = cast(uint)dest.vertices.length;
      foreach(vi; 0 .. prim.vertices.length) {
        Vertex nv = prim.vertices[vi];
        auto pp = inst.matrix.multiply([nv.position[0], nv.position[1], nv.position[2], 1.0f]);
        auto nn = inst.matrix.multiply([nv.normal[0],   nv.normal[1],   nv.normal[2],   0.0f]);
        nv.position = [pp[0], pp[1], pp[2]];
        nv.normal   = [nn[0], nn[1], nn[2]];
        dest.addVertex(nv);
      }
      foreach(ii; 0 .. prim.indices.length) dest.indices ~= base + prim.indices[ii];
    }
  }
  Bounds b;
  foreach(vi; 0 .. dest.vertices.length) b.update(dest.vertices[vi].position);
  float midY = midpoint(b.min, b.max)[1];
  foreach(vi; 0 .. dest.vertices.length) dest.vertices[vi].position[1] -= midY;
  dest.indices.invalidate();
}

/** Dwarven bodies, baked from the [ENTITY:Dwarf] L-system, rendered instanced. */
class Dwarves : OpenAsset {
  Dwarf[] dwarves;
  alias dwarves this;
  int selected = -1;
  size_t[] tickOrder;

  this() {
    super();
    foreach(ref e; entityTable) if(e.name == "Dwarf") { bakeEntity(this, e); break; }
    initInstanced(() => "Dwarves");
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
