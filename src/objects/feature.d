/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : translateScale;
import block : spawnBlock, unsettleBlocks;
import vegetation : saveVegetation, loadVegetation;

struct FeaturePartT {
  string mesh;
  float scaleX = 1.0f, scaleXVariance = 0.0f;
  float scaleY = 1.0f, scaleYVariance = 0.0f;
  float taper  = 0.0f;                          /// scaleX reduction per repeated segment
  float offsetY = 0.0f;                         /// 0.0 = ground, 1.0 = top (height * tileHeight)
  bool repeat  = false;                         /// repeat per height segment
  string resourceType = "None";                 /// DrawInstance material
}

struct FeatureDropT {
  string material;
  int countMin = 1, countMax = 1;
  bool perHeight = false;
}

struct FeatureT {
  string name;
  string[] spawnOn;
  float noiseThreshold = 0.65f;
  uint hashSeed1, hashSeed2;
  uint hashMod, hashRem;
  uint heightMin = 1, heightMax = 1;
  float tilePenalty = 0.0f;
  float progressRate = 0.25f;
  string interaction;
  FeaturePartT[] parts;
  FeatureDropT[] drops;
}

struct Feature {
  int[3] rootTile;
  uint height;
  size_t[] instanceIdxs;  // per part — for repeated parts, trunkStart only
  uint hash;

  bool matchIndex(size_t idx) const {
    foreach(pi, startIdx; instanceIdxs) {
      if(idx == startIdx) return true;
      if(idx > startIdx && idx < startIdx + height) return true;
    }
    return false;
  }
  @property float bboxHeight() const { return cast(float)height; }
}

Feature[] buildFeatureData(immutable(WorldData) wd, int[3] coord, const ResourceType[] tileTypes, ref immutable FeatureT ft) {
  import noise : noiseHTT;
  Feature[] result;
  for(int i = 0; i < wd.tileCount; i++) {
    if(tileTypes[i] == ResourceType.None) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    if(wd.getTile([wc[0], wc[1]+1, wc[2]]) != ResourceType.None) continue;
    auto tt = tileTypes[i];
    if(!ft.spawnOn.canFind(tt.to!string)) continue;
    auto n = noiseHTT(wc[0], wc[2], wd.seed);
    if(n[2] < ft.noiseThreshold) continue;
    uint hash = (wc[0] * ft.hashSeed1) ^ (wc[2] * ft.hashSeed2);
    if(hash % ft.hashMod != ft.hashRem) continue;
    uint height = ft.heightMin + (ft.heightMin == ft.heightMax ? 0 : cast(uint)((n[0]+n[1]) * (ft.heightMax-ft.heightMin) * 0.5f));
    result ~= Feature([wc[0], wc[1]+1, wc[2]], height, [], hash);
  }
  return result;
}

float getFeatureProgressRate(ref App app, int[3] tile) {
  foreach(ref ft; features) {
    if(ft.name !in app.world.features) continue;
    int[3] coord = app.world.chunkCoord(tile);
    if(coord !in app.world.features[ft.name]) continue;
    foreach(ref f; app.world.features[ft.name][coord]){ if(f.rootTile == tile) return ft.progressRate; }
  }
  return 0.25f;
}

Feature[] addFeatureInstances(ref App app, Feature[] features, ref immutable FeatureT ft, Geometry[string] meshes) {
  foreach(ref f; features) {
    auto wp = app.world.tileToWorld(f.rootTile);
    float th = app.world.tileHeight;
    f.instanceIdxs = [];
    foreach(ref part; ft.parts) {
      if(part.mesh !in meshes) continue;
      auto mesh = meshes[part.mesh];
      if(mesh is null) continue;
      f.instanceIdxs ~= mesh.instances.length;
      float sx = part.scaleX + (f.hash % 10) * part.scaleXVariance;
      float sy = part.scaleY < 0 ? th : part.scaleY + (f.hash % 5) * part.scaleYVariance;
      float oy = part.offsetY < 0 ? f.height * th : part.offsetY;
      auto rt = part.resourceType == "None" ? ResourceType.None : part.resourceType.to!ResourceType;
      if(part.repeat) {
        for(uint h = 0; h < f.height; h++) {
          app.world.data.tilePenalties[[f.rootTile[0], f.rootTile[1]+cast(int)h, f.rootTile[2]]] = ft.tilePenalty;
          float s = sx - h * part.taper;
          if(s < 0.05f) s = 0.05f;
          mesh.instances ~= DrawInstance(rt, translateScale([wp[0], wp[1] + h * th, wp[2]], [s, sy, s]));
        }
      } else {
        if(ft.tilePenalty > 0.0f) app.world.data.tilePenalties[f.rootTile] = ft.tilePenalty;
        mesh.instances ~= DrawInstance(rt, translateScale([wp[0], wp[1] + oy, wp[2]], [sx, sy, sx]));
      }
      mesh.markDirty();
    }
  }
  return features;
}

void rebuildAllFeatures(ref App app) {
  foreach(ref mesh; app.world.featureMeshes.values) mesh.instances = [];
  foreach(ref ft; features) {
    foreach(coord, ref chunkFeatures; app.world.features[ft.name]){
      chunkFeatures = app.addFeatureInstances(chunkFeatures, ft, app.world.featureMeshes);
    }
  }
  foreach(ref mesh; app.world.featureMeshes.values) mesh.markDirty();
}

void removeAllFeatures(ref App app, int[3] coord) {
  foreach(ref ft; features) app.world.features[ft.name].remove(coord);
  app.rebuildAllFeatures();
}

void interactFeaturesAt(ref App app, int[3] tile) {
  foreach(ref ft; features) {
    if(ft.name !in app.world.features) continue;
    int[3] coord = app.world.chunkCoord(tile);
    if(coord !in app.world.features[ft.name]) continue;
    foreach(i, ref f; app.world.features[ft.name][coord]) {
      if(f.rootTile != tile) continue;
      foreach(ref drop; ft.drops) {
        auto rt = drop.material.to!ResourceType;
        if(drop.perHeight) {
          for(uint h = 0; h < f.height; h++) app.spawnBlock([tile[0], tile[1]+cast(int)h, tile[2]], rt);
        } else {
          uint count = drop.countMin + (f.hash % max(1, drop.countMax - drop.countMin + 1));
          foreach(n; 0..count) app.spawnBlock(tile, rt);
        }
      }
      app.world.features[ft.name][coord] = app.world.features[ft.name][coord][0..i] ~ app.world.features[ft.name][coord][i+1..$];
      app.world.unsettleBlocks(app.world.blocks, tile);
      app.world.inventoryDirty = true;
      app.rebuildAllFeatures();
      return;
    }
  }
}
