/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import block : spawnBlock, unsettleBlocks;
import inventory : deriveInventory;
import matrix : translateScale, scale;
import vegetation : saveVegetation, getBestVegetation, loadVegetation, removeVegetation;

/** Shared instanced cylinder mesh for all tree trunks */
class TrunkMesh : Cylinder {
  this() {
    super(0.4f, 1.0f, 12);  // thin cylinder, 12 segments for perf
    initInstanced(() => "TrunkMesh");
  }
}
 
/** Shared instanced icosahedron mesh for all tree canopies */
class CanopyMesh : Icosahedron {
  this() {
    super();
    initInstanced(() => "CanopyMesh");
  }
}
 
/** A tree: root tile, height, instance indices into shared meshes */
struct Tree {
  int[3] rootTile;          /// World tile at base of tree
  uint height;              /// Number of trunk segments
  size_t trunkStart;        /// First instance index in TrunkMesh
  size_t canopyIdx;         /// Instance index in CanopyMesh
  uint hash;

  static bool matchGeometry(string g) { return g == "TrunkMesh" || g == "CanopyMesh"; }
  bool matchIndex(size_t idx) const { return (idx >= trunkStart && idx < trunkStart + height) || idx == canopyIdx; }
  @property float bboxHeight() const { return cast(float)height; }
}

bool getBestTree(ref App app, float[3][2] ray, Intersection[] hits, out int[3] rootTile) {
  return app.getBestVegetation!Tree(ray, hits, app.world.trees, rootTile);
}

/** Generate trees for a chunk based on tile types and noise */
Tree[] buildTreeData(immutable(WorldData) wd, int[3] coord, const ResourceType[] tileTypes) {
  import noise : noiseHTT;
  import tree : Tree;
  Tree[] trees;
  for (int i = 0; i < wd.tileCount; i++) {
    if (tileTypes[i] == ResourceType.None) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    int[3] above = [wc[0], wc[1]+1, wc[2]];
    if (wd.getTile(above) != ResourceType.None) continue;
    auto tt = tileTypes[i];
    if (tt != ResourceType.Grass01 && tt != ResourceType.Grass02 && tt != ResourceType.Forest01 && tt != ResourceType.Forest02) continue;
    auto n = noiseHTT(wc[0], wc[2], wd.seed);
    if (n[2] < 0.65f) continue;  // sparse placement — only high noise values get trees
    uint hash = (wc[0] * 2654435761u) ^ (wc[2] * 2246822519u);
    if (hash % 6 != 0) continue;  // ~1 in 8 eligible tiles gets a tree
    uint height = 1 + cast(uint)((n[0] + n[1]) * 6.0f);  // height 2-8, mix of both noises
    trees ~= Tree([wc[0], wc[1]+1, wc[2]], height, 0, 0, hash);
  }
  return trees;
}

/** Add tree instances to shared trunk/canopy meshes, returns trees with updated indices */
Tree[] addTreeInstances(ref App app, Tree[] trees) {
  foreach(ref t; trees) {
    auto wp = app.world.tileToWorld(t.rootTile);
    float px = wp[0], py = wp[1], pz = wp[2];
    float th = app.world.tileHeight;

    float baseRadius  = 0.6f + (t.hash % 10) * 0.02f;   // 0.6 - 0.8
    float cSize  = 1.2f + (t.hash % 8)  * 0.15f;   // 1.2 - 2.25
    float cSquish = 0.6f + (t.hash % 5) * 0.1f;    // 0.6 - 1.0

    t.trunkStart = app.world.trunk.instances.length;
    for(uint h = 0; h < t.height; h++) {
      app.world.data.tilePenalties[[t.rootTile[0], t.rootTile[1] + cast(int)h, t.rootTile[2]]] = 15.0f;
      float s = baseRadius - h * 0.015f;
      if(s < 0.05f) s = 0.05f;
      app.world.trunk.instances ~= DrawInstance(ResourceType.Wood, translateScale([px, py + h * th, pz], [s, th, s]));
    }
    app.world.canopy.instances ~= DrawInstance(ResourceType.Leaves, translateScale([px, py + t.height * th, pz], [cSize, cSize*cSquish, cSize]));
  }
  app.world.trunk.markDirty();
  app.world.canopy.markDirty();
  return trees;
}

void rebuildTreeInstances(ref App app) {
  foreach(key; app.world.data.tilePenalties.keys) {
    if(app.world.data.tilePenalties[key] < 20.0f) app.world.data.tilePenalties.remove(key);
  }
  app.world.trunk.instances = [];
  app.world.canopy.instances = [];
  foreach(chunkCoord, ref chunkTrees; app.world.trees){ chunkTrees = app.addTreeInstances(chunkTrees); }
  app.world.trunk.markDirty();
  app.world.canopy.markDirty();
}

/** Find and fell the tree rooted at or directly above the given tile */
void fellTree(ref App app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in app.world.trees) return;
  foreach(i, ref t; app.world.trees[coord]) {
    //if(t.rootTile != [tile[0], tile[1]+1, tile[2]]) continue;
    if(t.rootTile != tile) continue;
    // spawn wood blocks
    for(uint h = 0; h < t.height; h++) { app.spawnBlock([t.rootTile[0], t.rootTile[1] + cast(int)h, t.rootTile[2]], ResourceType.Wood); }
    app.deriveInventory();
    app.world.unsettleBlocks(app.world.blocks, t.rootTile);
    // remove from trees array
    app.world.trees[coord] = app.world.trees[coord][0..i] ~ app.world.trees[coord][i+1..$];
    app.rebuildTreeInstances();
    return;
  }
}

void saveTrees(ref App app) { app.saveVegetation!Tree(app.world.trees, app.world.pendingTrees, app.world.treePath()); }
void loadTrees(ref App app) { app.loadVegetation!Tree(app.world.pendingTrees, app.world.treePath()); }
void removeTreeInstances(ref App app, int[3] coord) { app.removeVegetation!(Tree, rebuildTreeInstances)(app.world.trees, coord); }
