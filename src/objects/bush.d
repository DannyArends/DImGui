/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : spawnBlock;
import intersection : intersects;
import matrix : translateScale;
import noise : noiseHTT;
import serialization : readWorldData, writeWorldData;
import vegetation : saveVegetation, loadVegetation, removeVegetation;
import world : noTile;

class BushMesh : Icosahedron {
  this() {
    super();
    initInstanced(() => "BushMesh");
  }
}

struct Bush {
  int[3] rootTile;
  size_t bushIdx;
  uint hash;
}

Bush[] buildBushData(immutable(WorldData) wd, int[3] coord, const ResourceType[] tileTypes) {
  Bush[] bushes;
  for (int i = 0; i < wd.tileCount; i++) {
    if (tileTypes[i] == ResourceType.None) continue;
    auto tt = tileTypes[i];
    if (tt != ResourceType.Grass01 && tt != ResourceType.Grass02 && tt != ResourceType.Forest01 && tt != ResourceType.Forest02) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    int[3] above = [wc[0], wc[1]+1, wc[2]];
    if (wd.getTile(above) != ResourceType.None) continue;
    auto n = noiseHTT(wc[0], wc[2], wd.seed);
    if (n[2] < 0.55f) continue;           // slightly lower threshold than trees
    uint hash = (wc[0] * 1234567891u) ^ (wc[2] * 987654321u);
    if (hash % 8 != 1) continue;          // different modulus so bushes/trees don't overlap
    bushes ~= Bush([wc[0], wc[1]+1, wc[2]], 0, hash);
  }
  return bushes;
}

Bush[] addBushInstances(ref App app, Bush[] bushes) {
  foreach(ref b; bushes) {
    auto wp = app.world.tileToWorld(b.rootTile);
    float sz = 0.6f + (b.hash % 6) * 0.05f;   // 0.6 - 0.85, smaller than canopy
    b.bushIdx = app.world.bush.instances.length;
    app.world.bush.instances ~= DrawInstance(ResourceType.Leaves, translateScale([wp[0], wp[1], wp[2]], [sz, sz * 0.5f, sz]));
  }
  app.world.bush.markDirty();
  return bushes;
}

void rebuildBushInstances(ref App app) {
  app.world.bush.instances = [];
  foreach(chunkCoord, ref chunkBushes; app.world.bushes)
    chunkBushes = app.addBushInstances(chunkBushes);
  app.world.bush.markDirty();
}

void gatherBush(ref App app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in app.world.bushes) return;
  foreach(i, ref b; app.world.bushes[coord]) {
    if(b.rootTile != tile) continue;
    uint count = 3 + (b.hash % 3);
    foreach(n; 0..count) app.spawnBlock(tile, ResourceType.Berry);
    app.world.bushes[coord] = app.world.bushes[coord][0..i] ~ app.world.bushes[coord][i+1..$];
    app.rebuildBushInstances();
    return;
  }
}

bool getBestBush(ref App app, float[3][2] ray, Intersection[] hits, out int[3] rootTile) {
  Intersection best;
  foreach(ref hit; hits) {
    auto obj = app.objects[hit.idx[0]];
    if(obj.geometry() != "BushMesh") continue;
    foreach(ref bushes; app.world.bushes.values) foreach(ref b; bushes) {
      if(hit.idx[1] != b.bushIdx) continue;
      auto wp = app.world.tileToWorld(b.rootTile);
      float[3] bmin = [wp[0] - 1.0f, wp[1], wp[2] - 1.0f];
      float[3] bmax = [wp[0] + 1.0f, wp[1] + 1.5f, wp[2] + 1.0f];
      auto i = ray.intersects(bmin, bmax, hit.idx[0], hit.idx[1]);
      if(i.intersects && (!best.intersects || i.tmin < best.tmin)) { best = i; rootTile = b.rootTile; }
    }
  }
  return best.intersects;
}

void saveBushes(ref App app) { app.saveVegetation!Bush(app.world.bushes, app.world.pendingBushes, app.world.bushPath()); }
void loadBushes(ref App app) { app.loadVegetation!Bush(app.world.pendingBushes, app.world.bushPath()); }
void removeBushInstances(ref App app, int[3] coord) { app.removeVegetation!(Bush, rebuildBushInstances)(app.world.bushes, coord); }