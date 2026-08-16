/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import assimp : OpenAsset;
import matrix : multiply, translate, rotate, position, scale, translateScale;

/** A pawn's full per-uid rig+animation state. Owned solely by the container's Skeleton[uint] map; never drawn. */
struct Skeleton {
  RigNode[] rig;             /// turtle rig, parent-indexed, walked to emit brush instances
  float[3] dscale;           /// build girth/height, seeded by uid
  float footY;               /// lowest bind-pose Y, to seat feet on the ground
  Node rootnode;             /// posed each frame
  Bone[string] bones;        /// name -> (local index, inverse bind), merged into app.bones
  Animation[] animations;    /// baked clips
  AnimationState state;      /// single clip state
  int region;                /// palette base in boneOffsets
  uint boneBase, boneCount;  /// global bone range
  int[] boneSlot;            /// node k -> local palette slot
  string name;               /// "Species:skel:uid"
}

/** Dwarven bodies, baked from the [ENTITY:Dwarf] L-system, rendered instanced. */
class Dwarves : Geometry {
  Dwarf[] dwarves;
  alias dwarves this;
  int selected = -1;
  size_t[] tickOrder;
  Geometry[string] meshes;          /// shared brush geometry per mesh name (Cube/Cylinder/Sphere)
  Skeleton[uint] skel;              /// per-uid rig + skeleton + animation

  this() {
    super();
    initInstanced("Dwarves");
  }

  mixin SwapRemove!dwarves;
}

/** Data-driven foraging animals, rendered as instanced tori */
class Animals : Geometry {
  Animal[] animals;
  alias animals this;
  int selected = -1;
  size_t[] tickOrder;
  Geometry[string] meshes;          /// shared brush geometry per mesh name (Cube/Cylinder/Sphere)
  Skeleton[uint] skel;              /// per-uid rig + skeleton + animation

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
