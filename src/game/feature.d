/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock, unsettleBlocks;
import game : GameApp;
import matrix : translateScale;
import normals : computeTangents;
import noise : noiseHTT;
import sfx : play;
import tile : getTile, tileCoord, tileToWorld;
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
  string sound;
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

string delegate() captureKey(string k) { return () => k; }

void initFeatureMeshes(ref GameApp app) {
  foreach(ref ft; features) {
    foreach(ref part; ft.parts) {
      string meshKey = ft.name ~ ":" ~ part.mesh;
      if(meshKey in app.world.featureMeshes) continue;
      Geometry mesh;
      if(part.mesh == "Cylinder") { mesh = new Cylinder(0.4f, 1.0f, 12); mesh.initInstanced(captureKey(meshKey)); }
      if(part.mesh == "Icosahedron") { mesh = new Icosahedron(); mesh.computeTangents(); mesh.initInstanced(captureKey(meshKey)); }
      app.world.featureMeshes[meshKey] = mesh;
      app.objects ~= mesh;
    }
  }
}

Feature[] buildFeatureData(immutable(WorldData) wd, int[3] coord, const ResourceType[] tileTypes, const FeatureT ft) {
  Feature[] result;
  ResourceType[] spawnTypes;
  foreach(s; ft.spawnOn) spawnTypes ~= s.to!ResourceType;
  for(int i = 0; i < wd.tileCount; i++) {
    if(tileTypes[i] == ResourceType.None) continue;
    if(i + wd.chunkSize < wd.tileCount && tileTypes[i + wd.chunkSize] != ResourceType.None) continue;
    if(!spawnTypes.canFind(tileTypes[i])) continue;
    auto lc = wd.tileCoord(i);
    auto wc = wd.worldCoord(coord, lc);
    auto n = noiseHTT(wc[0], wc[2], wd.seed);  // recompute — only for surface spawn candidates
    if(n[2] < ft.noiseThreshold) continue;
    uint hash = (wc[0] * ft.hashSeed1) ^ (wc[2] * ft.hashSeed2);
    if(hash % ft.hashMod != ft.hashRem) continue;
    uint height = ft.heightMin + (ft.heightMin == ft.heightMax ? 0 : cast(uint)((n[0]+n[1]) * (ft.heightMax-ft.heightMin) * 0.5f));
    result ~= Feature([wc[0], wc[1]+1, wc[2]], height, [], hash);
  }
  return result;
}

float getFeatureProgressRate(ref GameApp app, int[3] tile) {
  foreach(ref ft; features) {
    if(ft.name !in app.world.features) continue;
    int[3] coord = app.world.chunkCoord(tile);
    if(coord !in app.world.features[ft.name]) continue;
    foreach(ref f; app.world.features[ft.name][coord]){ if(f.rootTile == tile) return ft.progressRate; }
  }
  return 0.25f;
}

Feature[] addFeatureInstances(ref GameApp app, Feature[] features, ref immutable FeatureT ft, ref Geometry[string] meshes) {
  foreach(ref f; features) {
    auto wp = app.world.tileToWorld(f.rootTile);
    float th = app.world.tileHeight;
    f.instanceIdxs = [];
    foreach(ref part; ft.parts) {
      string meshKey = ft.name ~ ":" ~ part.mesh;
      if(meshKey !in meshes) continue;
      auto mesh = meshes[meshKey];
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
          mesh.instances ~= DrawInstance([cast(uint)rt, cast(uint)rt], translateScale([wp[0], wp[1] + h * th, wp[2]], [s, sy, s]));
        }
      } else {
        if(ft.tilePenalty > 0.0f) app.world.data.tilePenalties[f.rootTile] = ft.tilePenalty;
        mesh.instances ~= DrawInstance([cast(uint)rt, cast(uint)rt], translateScale([wp[0], wp[1] + oy, wp[2]], [sx, sy, sx]));
      }
      mesh.instances.invalidate();
    }
  }
  return features;
}

void rebuildAllFeatures(ref GameApp app) {
  app.world.data.tilePenalties = null;
  foreach(ref mesh; app.world.featureMeshes.values) mesh.instances = [];
  foreach(ref ft; features) {
    foreach(coord, ref chunkFeatures; app.world.features[ft.name]){
      if(coord !in app.world.chunks) continue;
      chunkFeatures = app.addFeatureInstances(chunkFeatures, ft, app.world.featureMeshes);
    }
  }
  foreach(ref mesh; app.world.featureMeshes.values){ mesh.instances.invalidate(); }
}

void removeAllFeatures(ref GameApp app, int[3] coord) {
  if(coord !in app.world.featuresModified) {
    foreach(ref ft; features) { 
      if(auto p = coord in app.world.features[ft.name]) { if((*p).length > 0){ app.world.features[ft.name].remove(coord); } }
    }
  }
  app.rebuildAllFeatures();
}

/** True if a feature with the given interaction is rooted at this tile */
bool hasFeature(ref GameApp app, int[3] tile, string interaction) {
  foreach(ref ft; features) {
    if(ft.interaction != interaction || ft.name !in app.world.features) continue;
    int[3] coord = app.world.chunkCoord(tile);
    if(coord !in app.world.features[ft.name]) continue;
    foreach(ref f; app.world.features[ft.name][coord]) if(f.rootTile == tile) return true;
  }
  return false;
}

void dropPending(ref GameApp app, const FeatureT ft, int[3] coord, int[3] tile) {
  if(ft.name !in app.world.pendingFeatures || coord !in app.world.pendingFeatures[ft.name]) return;
  app.world.pendingFeatures[ft.name][coord] = app.world.pendingFeatures[ft.name][coord].filter!(pf => pf.rootTile != tile).array;
}

/** Harvest every feature of type `ft` rooted at `tile` (spawns drops, removes the feature). Returns true if any harvested. */
bool harvestFeatureType(ref GameApp app, const FeatureT ft, int[3] tile, int[3] coord) {
  if(ft.name !in app.world.features || coord !in app.world.features[ft.name]) return false;
  bool any = false;
  for(size_t i = 0; i < app.world.features[ft.name][coord].length; ) {
    auto f = app.world.features[ft.name][coord][i];
    if(f.rootTile != tile) { i++; continue; }
    foreach(ref drop; ft.drops) {
      auto rt = drop.material.to!ResourceType;
      if(!drop.perHeight) {
        uint count = drop.countMin + (f.hash % max(1, drop.countMax - drop.countMin + 1));
        foreach(n; 0..count){ app.spawnBlock(tile, rt); }
      } else { for(uint h = 0; h < f.height; h++){ app.spawnBlock([tile[0], tile[1]+cast(int)h, tile[2]], rt); } }
    }
    app.world.features[ft.name][coord] = app.world.features[ft.name][coord][0..i] ~ app.world.features[ft.name][coord][i+1..$];
    app.dropPending(ft, coord, tile);
    app.world.featuresModified[coord] = true;
    if(ft.sound.length){ app.play(ft.sound, 0.2f); }
    any = true;
  }
  return any;
}
void interactFeaturesAt(ref GameApp app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  bool any = false;
  foreach(const ft; features) any |= app.harvestFeatureType(ft, tile, coord);
  if(any) {
    app.world.unsettleBlocks(app.world.blocks, tile);
    app.rebuildAllFeatures();
  }
}
