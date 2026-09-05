/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : noBlock;
import matrix : multiply, translate, rotate, position, scale, translateScale;

/** Instanced roster of pawns of type T, backed by a swap-removable array. */
class Pawns(Pawn, string label) : Geometry if(is(typeof(Pawn.init.entity) == Entity!N, uint N)) {
  Pawn[] items;                     /// Backing roster of Pawns (each is-an Entity via alias this)
  alias items this;
  int selected = -1;                /// Selected index, -1 = none
  size_t[] tickOrder;               /// Shuffled per-tick iteration order
  Geometry[string] meshes;          /// shared brush geometry per mesh name (Cube/Cylinder/Sphere)
  Skeleton[uint] skel;              /// per-uid rig + skeleton + animation

  this() { super(); initInstanced(label); }

  mixin SwapRemove!items;
}

/** Dwarven bodies, baked from the [ENTITY:Dwarf] L-system, rendered instanced. */
class Dwarves : Pawns!(Dwarf, "Dwarves") { alias dwarves = items; alias dwarves this; }

/** Data-driven foraging animals, rendered as instanced tori */
class Animals : Pawns!(Animal, "Animals") { alias animals = items; alias animals this; int selectedType = -1; }

/** Build one instanced primitive for `mesh`, register it on `into`, and add it to the scene. */
void buildInstancedMesh(ref GameApp app, ref Geometry[string] into, string prefix, string mesh) {
  if(mesh in into) return;
  auto m = makePrimitive(mesh);
  if(m is null) return;
  m.initInstanced(prefix ~ ":" ~ mesh);
  m.animations.length = 1;   // select the ANIMATED pipeline; boneCount stays 0 so updateMeshInfo leaves meshdef[3] alone
  m.movable = true;
  into[mesh] = m;
  app.objects ~= m;
}

/** Renderable cube geometry for individual blocks within a chunk, not selectable */
class Tiles : Square {
  this(ChunkData cd) {
    super();
    initInstanced("Tiles", cd.tileInstances);
    isSelectable = false;
    hideInObjectsWindow = true;
    globalNormals = true;
  }
}

/** Selectable chunk AABB proxy (renders nothing itself); terrain is its Tiles member */
class Chunk : BoundingBox {
  ChunkData data;
  Geometry tiles;
  bool rebuild = false;
  alias data this;

  this(ChunkData cd, immutable(WorldData) wd) {
    super();
    tiles = new Tiles(data = cd);
    indices = [];                   // Hide from rendering
    hideInObjectsWindow = true;     // Hide from window
    float ox = cd.coord[0] * wd.chunkWorldSize, oz = cd.coord[2] * wd.chunkWorldSize;
    setDimensions([ox, wd.yOffset, oz], [ox + wd.chunkWorldSize, wd.yOffset + wd.height, oz + wd.chunkWorldSize]);
    instances = [DrawInstance()];
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
  Ingredient need;
  uint blockID = noBlock;
}

class GhostCube : Cube {
  ResourceType type = ResourceType.None;
  ToolMode activeTool = isAndroid ? ToolMode.Info : ToolMode.Select;
  PaintState paint;
  PendingBuild[] buildSelection;   /// Tiles awaiting a block-type choice
  string placingWorkshop = "";     /// chosen workshop ("" = landscaping/tile mode)
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
