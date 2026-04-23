/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import block : spawnDroppedBlock;
import io : readFile, writeFile;
import tileatlas : TileType;
import world : tileToWorld, WORLD_MAGIC;

/** Shared instanced cylinder mesh for all tree trunks */
class TrunkMesh : Cylinder {
  this() {
    super(0.2f, 1.0f, 12);  // thin cylinder, 12 segments for perf
    instancedMesh = true;
    instances = [];
    geometry = (){ return "TrunkMesh"; };
  }
}
 
/** Shared instanced icosahedron mesh for all tree canopies */
class CanopyMesh : Icosahedron {
  this() {
    super();
    instancedMesh = true;
    instances = [];
    geometry = (){ return "CanopyMesh"; };
  }
}
 
/** A tree: root tile, height, instance indices into shared meshes */
struct Tree {
  int[3] rootTile;          /// World tile at base of tree
  uint height;              /// Number of trunk segments
  size_t trunkStart;        /// First instance index in TrunkMesh
  size_t canopyIdx;         /// Instance index in CanopyMesh
  uint hash;
}

/** Generate trees for a chunk based on tile types and noise */
Tree[] buildTreeData(immutable(WorldData) wd, int[3] coord, const TileType[] tileTypes) {
  import noise : noiseHTT;
  import tree : Tree;
  Tree[] trees;
  for (int i = 0; i < wd.tileCount; i++) {
    if (tileTypes[i] == TileType.None) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    int[3] above = [wc[0], wc[1]+1, wc[2]];
    if (wd.getTile(above) != TileType.None) continue;
    auto tt = tileTypes[i];
    if (tt != TileType.Grass01 && tt != TileType.Grass02 &&
        tt != TileType.Forest01 && tt != TileType.Forest02) continue;
    auto n = noiseHTT(wc[0], wc[2], wd.seed);
    if (n[2] < 0.65f) continue;  // sparse placement — only high noise values get trees
    uint hash = (wc[0] * 2654435761u) ^ (wc[2] * 2246822519u);
    if (hash % 6 != 0) continue;  // ~1 in 8 eligible tiles gets a tree
    uint height = 1 + cast(uint)((n[0] + n[1]) * 2.0f);  // height 2-8, mix of both noises
    trees ~= Tree([wc[0], wc[1]+1, wc[2]], height, 0, 0, hash);
  }
  return trees;
}

/** Add tree instances to shared trunk/canopy meshes, returns trees with updated indices */
Tree[] addTreeInstances(ref App app, Tree[] trees) {
  foreach(ref t; trees) {
    auto wp = app.tileToWorld(t.rootTile);
    float px = wp[0], py = wp[1], pz = wp[2];
    float th = app.world.tileHeight;

    float baseRadius  = 0.6f + (t.hash % 10) * 0.02f;   // 0.6 - 0.8
    float cSize  = 1.2f + (t.hash % 8)  * 0.15f;   // 1.2 - 2.25
    float cSquish = 0.6f + (t.hash % 5) * 0.1f;    // 0.6 - 1.0

    t.trunkStart = app.world.trunk.instances.length;
    for(uint h = 0; h < t.height; h++) {
      float s = baseRadius - h * 0.015f;
      if(s < 0.05f) s = 0.05f;
      app.world.trunk.instances ~= Instance(cast(uint)TileType.Wood, [s, 0, 0,  0, th, 0,  0, 0, s,  px, py + h * th, pz]);
    }

    t.canopyIdx = app.world.canopy.instances.length;
    app.world.canopy.instances ~= Instance(cast(uint)TileType.Leaves, [cSize, 0, 0,  0, cSize * cSquish, 0,  0, 0, cSize, px, py + t.height * th, pz]);
  }
  app.world.trunk.buffers[INSTANCE] = false;
  app.world.canopy.buffers[INSTANCE] = false;
  return trees;
}

/** Remove tree instances for a chunk from shared meshes */
void removeTreeInstances(ref App app, int[3] coord) {
  if(coord !in app.world.trees) return;
  app.world.trees.remove(coord);
  // rebuild all instances from remaining trees
  app.world.trunk.instances = [];
  app.world.canopy.instances = [];
  foreach(chunkCoord, ref chunkTrees; app.world.trees) {
    chunkTrees = app.addTreeInstances(chunkTrees);
  }
  app.world.trunk.buffers[INSTANCE] = false;
  app.world.canopy.buffers[INSTANCE] = false;
}

/** Find and fell the tree rooted at or directly above the given tile */
void fellTree(ref App app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in app.world.trees) return;
  foreach(i, ref t; app.world.trees[coord]) {
    if(t.rootTile != [tile[0], tile[1]+1, tile[2]]) continue;

    // remove trunk instances
    size_t trunkEnd = t.trunkStart + t.height;
    app.world.trunk.instances = app.world.trunk.instances[0..t.trunkStart] ~ app.world.trunk.instances[trunkEnd..$];
    // remove canopy instance
    app.world.canopy.instances = app.world.canopy.instances[0..t.canopyIdx] ~ app.world.canopy.instances[t.canopyIdx+1..$];

    // update indices of ALL other trees
    foreach(ref other; app.world.trees) {
      foreach(ref ot; other) {
        if(ot.trunkStart > t.trunkStart) ot.trunkStart -= t.height;
        if(ot.canopyIdx  > t.canopyIdx)  ot.canopyIdx  -= 1;
      }
    }

    app.world.trunk.buffers[INSTANCE] = false;
    app.world.canopy.buffers[INSTANCE] = false;

    // spawn wood blocks
    for(uint h = 0; h < t.height; h++) { app.spawnDroppedBlock([t.rootTile[0], tile[1], t.rootTile[2]], TileType.Wood); }
    app.world.trees[coord] = app.world.trees[coord][0..i] ~ app.world.trees[coord][i+1..$];
    return;
  }
}

void saveTrees(ref App app) {
  if(app.world.trees.length == 0) return;
  Tree[] allTrees;
  foreach(trees; app.world.trees.values) allTrees ~= trees;
  uint[2] header = [WORLD_MAGIC, cast(uint)allTrees.length];
  writeFile(app.world.treePath(), cast(char[])(cast(ubyte[])header ~ cast(ubyte[])allTrees));
}

void loadTrees(ref App app) {
  auto raw = readFile(app.world.treePath());
  if(raw.length < uint[2].sizeof) return;
  if((cast(uint[])raw)[0] != WORLD_MAGIC) return;
  auto trees = cast(Tree[])raw[uint[2].sizeof..$].dup;
  foreach(ref t; trees) {
    int[3] coord = app.world.chunkCoord(t.rootTile);
    app.world.pendingTrees[coord] ~= t;  // use pendingTrees instead
  }
}

