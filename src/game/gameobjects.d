/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import assimp : OpenAsset;
import matrix : multiply, translate, rotate, position, scale, translateScale;

/** Dwarven bodies, baked from the [ENTITY:Dwarf] L-system, rendered instanced. */
class Dwarves : OpenAsset {
  Dwarf[] dwarves;
  alias dwarves this;
  int selected = -1;
  size_t[] tickOrder;
  Geometry[string] meshes;          /// shared brush geometry per mesh name (Cube/Cylinder/Sphere)
  RigNode[][uint] rig;              /// per-dwarf turtle rig (parent-indexed, walked by globals)
  float[3][uint] dscale;            /// per-dwarf build (girth/height), seeded by uid
  float[uint] footY;                /// per-dwarf lowest bind-pose Y, to seat feet on the ground

  this() {
    super();
    initInstanced("Dwarves");
  }

  mixin SwapRemove!dwarves;
}

/** Data-driven foraging animals, rendered as instanced tori */
class Animals : OpenAsset {
  Animal[] animals;
  alias animals this;
  int selected = -1;
  size_t[] tickOrder;
  Geometry[string] meshes;          /// shared brush geometry per mesh name (Cube/Cylinder/Sphere)
  RigNode[][uint] rig;              /// per-dwarf turtle rig (parent-indexed, walked by globals)
  float[3][uint] dscale;            /// per-dwarf build (girth/height), seeded by uid
  float[uint] footY;                /// per-dwarf lowest bind-pose Y, to seat feet on the ground

  this() {
    super();
    initInstanced("Animals");
  }
  mixin SwapRemove!animals;
}

/** Renderable cube geometry for individual blocks within a chunk, not selectable */
class Tiles : Square {
  this(ChunkData cd) {
    super();
    initInstanced("Tiles", cd.tileInstances);
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
    mName = "Chunk";
  }
}

/** Drifting voxel clouds above the world */
class Clouds : Square {
  this() {
    super();
    initInstanced("Clouds");
    isSelectable = false;
    castShadow = false;
    hideInObjectsWindow = true;
  }
}

class WaterTiles : Square {
  this() {
    super();
    initInstanced("WaterTiles");
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
    mName = typeof(this).stringof;
    initInstanced("BuildingGhosts");
  }
}

class PathMarkers : Cylinder {
  this() {
    super(0.1f, 0.2f, 6);
    initInstanced("PathMarkers");
  }
}
