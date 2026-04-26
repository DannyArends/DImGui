/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import block : spawnBlock;
import io : readFile, writeFile;
import tileatlas : TileType;
import matrix : translate, multiply, scale;
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
      app.world.trunk.instances ~= Instance([cast(uint)TileType.Wood, cast(uint)TileType.Wood], 
                                             translate([px, py + h * th, pz]).multiply(scale([s, th, s])));

    }
    app.world.canopy.instances ~= Instance([cast(uint)TileType.Leaves, cast(uint)TileType.Leaves], 
                                            translate([px, py + t.height * th, pz]).multiply(scale([cSize, cSize * cSquish, cSize])));
  }
  app.world.trunk.buffers[INSTANCE] = false;
  app.world.canopy.buffers[INSTANCE] = false;
  return trees;
}

void rebuildTreeInstances(ref App app) {
  app.world.trunk.instances = [];
  app.world.canopy.instances = [];
  foreach(chunkCoord, ref chunkTrees; app.world.trees){ chunkTrees = app.addTreeInstances(chunkTrees); }
}

/** Remove tree instances for a chunk from shared meshes */
void removeTreeInstances(ref App app, int[3] coord) {
  if(coord !in app.world.trees) return;
  app.world.trees.remove(coord);
  app.rebuildTreeInstances();
  app.world.trunk.buffers[INSTANCE] = false;
  app.world.canopy.buffers[INSTANCE] = false;
}

/** Find and fell the tree rooted at or directly above the given tile */
void fellTree(ref App app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in app.world.trees) return;
  foreach(i, ref t; app.world.trees[coord]) {
    if(t.rootTile != [tile[0], tile[1]+1, tile[2]]) continue;
    // spawn wood blocks
    for(uint h = 0; h < t.height; h++) { app.spawnBlock([t.rootTile[0], t.rootTile[1] + cast(int)h, t.rootTile[2]], TileType.Wood); }
    // remove from trees array
    app.world.trees[coord] = app.world.trees[coord][0..i] ~ app.world.trees[coord][i+1..$];
    app.rebuildTreeInstances();
    return;
  }
}

void saveTrees(ref App app) {
  Tree[] allTrees;
  foreach(trees; app.world.trees.values) allTrees ~= trees;
  foreach(trees; app.world.pendingTrees.values) allTrees ~= trees;
  if(allTrees.length == 0) return;
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

