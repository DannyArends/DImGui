/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import matrix : translateScale;

/** Dwarven Cylinderz */
class Dwarves : Cylinder {
  Dwarf[] dwarves;
  alias dwarves this;

  this() {
    super(0.5f, 1.0f, 6);
    initInstanced(() => "Dwarves");
  }
}

/** Renderable cube geometry for individual blocks within a chunk, not selectable */
class Tiles : Square {
  this(ChunkData cd) {
    super();
    initInstanced(() => "Tiles", cd.tileInstances);
    isSelectable = false;
  }
}

/** Spatial container for a chunk, selectable via its AABB, delegates rendering to Block */
class Chunk : Cube {
  ChunkData data;
  Geometry tiles;
  bool dirty = false;
  alias data this;

  this(ChunkData cd, WorldData wd) {
    super();
    data = cd;
    skipBoundingBox = true;
    indices = [];
    float sx = wd.chunkWorldSize;
    float sy = wd.chunkHeight * wd.tileHeight;
    float cx = data.coord[0] * sx + sx * 0.5f;
    float cz = data.coord[2] * sx + sx * 0.5f;
    float cy = sy * 0.5f + wd.yOffset;
    instances = [DrawInstance([0,0], translateScale([cx, cy, cz], [sx, sy, sx]))];
    tiles = new Tiles(cd);
    geometry = (){ return "Chunk"; };
  }
}

class GhostCube : Cube {
  ResourceType type = ResourceType.None;
  ToolMode activeTool = ToolMode.Select;
  PaintState paint;
  int[3] tile = noTile;
  int[3][] mineDesignations;
  int[3][] buildDesignations;
  bool ghostsDirty = false;
  int cachedMatIdx = -1;

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
