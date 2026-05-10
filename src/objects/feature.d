/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

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
  string interaction;
  FeaturePartT[] parts;
  FeatureDropT[] drops;
}

struct Feature {
  int[3] rootTile;
  uint height;
  size_t[] instanceIdxs;  // per part — for repeated parts, trunkStart only
  uint hash;

  bool matchIndex(size_t idx) const { return instanceIdxs.canFind(idx); }
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
    uint height = ft.heightMin == ft.heightMax ? ft.heightMin : ft.heightMin + cast(uint)((n[0] + n[1]) * (ft.heightMax - ft.heightMin) * 0.5f);
    result ~= Feature([wc[0], wc[1]+1, wc[2]], height, [], hash);
  }
  return result;
}

Feature[] addFeatureInstances(ref App app, Feature[] features, ref immutable FeatureT ft, Geometry[string] meshes) {
  foreach(ref f; features) {
    auto wp = app.world.tileToWorld(f.rootTile);
    float th = app.world.tileHeight;
    f.instanceIdxs = [];
    foreach(ref part; ft.parts) {
      float sx = part.scaleX + (f.hash % 10) * part.scaleXVariance;
      float sy = part.scaleY < 0 ? th : part.scaleY + (f.hash % 5) * part.scaleYVariance;
      float oy = part.offsetY < 0 ? f.height * th : part.offsetY;
      auto mesh = meshes[part.mesh];
      f.instanceIdxs ~= mesh.instances.length;
      if(part.repeat) {
        for(uint h = 0; h < f.height; h++) {
          app.world.data.tilePenalties[[f.rootTile[0], f.rootTile[1]+cast(int)h, f.rootTile[2]]] = ft.tilePenalty;
          float s = sx - h * part.taper;
          if(s < 0.05f) s = 0.05f;
          auto rt = part.resourceType == "None" ? ResourceType.None : part.resourceType.to!ResourceType;
          mesh.instances ~= DrawInstance(rt, translateScale([wp[0], wp[1] + h * th, wp[2]], [s, sy, s]));
        }
      } else {
        app.world.data.tilePenalties[f.rootTile] = ft.tilePenalty;
        auto rt = part.resourceType == "None" ? ResourceType.None : part.resourceType.to!ResourceType;
        mesh.instances ~= DrawInstance(rt, translateScale([wp[0], wp[1] + oy, wp[2]], [sx, sy, sx]));
      }
      mesh.markDirty();
    }
  }
  return features;
}

void rebuildFeatureInstances(ref App app, Feature[][int[3]] features, ref immutable FeatureT ft, Geometry[string] meshes) {
  foreach(ref mesh; meshes.values) mesh.instances = [];
  foreach(key; app.world.data.tilePenalties.keys) {
    if(app.world.data.tilePenalties[key] == ft.tilePenalty){ app.world.data.tilePenalties.remove(key); }
  }
  foreach(coord, ref chunkFeatures; features) { chunkFeatures = app.addFeatureInstances(chunkFeatures, ft, meshes); }
  foreach(ref mesh; meshes.values) { mesh.markDirty(); }
}

void interactFeature(ref App app, int[3] tile, ref immutable FeatureT ft, Feature[][int[3]] features) {
  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in features) return;
  foreach(i, ref f; features[coord]) {
    if(f.rootTile != tile) continue;
    foreach(ref drop; ft.drops) {
      auto rt = drop.material.to!ResourceType;
      uint count = drop.perHeight ? f.height : drop.countMin + (f.hash % max(1, drop.countMax - drop.countMin + 1));
      foreach(n; 0..count){ app.spawnBlock(tile, rt); }
    }
    features[coord] = features[coord][0..i] ~ features[coord][i+1..$];
    app.world.unsettleBlocks(app.world.blocks, tile);
    app.world.inventoryDirty = true;
    return;
  }
}

void removeAllFeatures(ref App app, int[3] coord) {
  import raws : features;
  bool changed = false;
  foreach(ref ft; features) {
    if(coord !in app.world.features[ft.name]) continue;
    app.world.features[ft.name].remove(coord);
    changed = true;
  }
  if(changed) foreach(ref ft; features){ app.rebuildFeatureInstances(app.world.features[ft.name], ft, app.world.featureMeshes); }
}