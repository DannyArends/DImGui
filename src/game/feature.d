/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock, unsettleBlocks;
import game : GameApp;
import lsystem : buildGrammar;
import matrix : translateScale;
import normals : computeTangents;
import noise : noiseHTT;
import sfx : play;
import tile : getTile, tileCoord, tileToWorld;
import turtle : interpret;
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

/** One drawing-symbol -> primitive brush for an L-system part (the data half of TurtleBrush). */
struct LSystemBrushT {
  char symbol;                                  /// grammar symbol, e.g. 'Y' or 'I'
  string mesh;                                  /// primitive mesh name: "Cylinder", "Icosahedron", ...
  string resourceType = "None";                 /// DrawInstance material
  float radius = 0.1f;                          /// local X/Z scale
  float length = 1.0f;                          /// local Y scale / segment length
  bool advance = true;                          /// move turtle forward after drawing
}

/** One weighted production rule: predecessor symbol -> production string, with probability. */
struct LSystemRuleT {
  char predecessor;                             /// e.g. 'X'
  string production;                            /// e.g. "Y[+X][-X]"
  uint probability = 100;                       /// weight (rules with same predecessor sum to 100)
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
  float lsystemAngle = 25.0f;                   /// L-system turn angle; brushes empty = no L-system
  LSystemBrushT[] brushes;                      /// single-level array, converts to immutable like parts/drops
  string axiom = "X";                           /// L-system start symbol(s)
  LSystemRuleT[] rules;                         /// L-system production rules
}

struct Feature {
  int[3] rootTile;
  uint height;
  size_t[2][] instanceRuns;  // [start, count) ranges across this feature's meshes
  uint hash;

  bool matchIndex(size_t idx) const {
    foreach(run; instanceRuns)
      if(idx >= run[0] && idx < run[0] + run[1]) return true;
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
    foreach(ref br; ft.brushes) {     // L-system brush meshes
      string meshKey = ft.name ~ ":" ~ br.mesh;
      if(meshKey in app.world.featureMeshes) continue;
      Geometry mesh;
      if(br.mesh == "Cylinder") { mesh = new Cylinder(0.4f, 1.0f, 12); mesh.initInstanced(captureKey(meshKey)); }
      if(br.mesh == "Icosahedron") { mesh = new Icosahedron(); mesh.computeTangents(); mesh.initInstanced(captureKey(meshKey)); }
      if(br.mesh == "Cone") { mesh = new Cone(0.5f, 1.0f, 12); mesh.initInstanced(captureKey(meshKey)); }
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

private string brushMesh(ref immutable FeatureT ft, char sym) {
  foreach(ref br; ft.brushes) if(br.symbol == sym) return br.mesh;
  return "";
}

/** Stamp one static part: emit its instances and record the index range on the feature. */
private void doPart(ref GameApp app, ref Feature f, ref immutable FeatureT ft, ref immutable FeaturePartT part, ref Geometry[string] meshes, float[3] wp, float th) {
  string meshKey = ft.name ~ ":" ~ part.mesh;
  if(meshKey !in meshes) return;
  auto mesh = meshes[meshKey];
  if(mesh is null) return;
  size_t partStart = mesh.instances.length;
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
  f.instanceRuns ~= [partStart, mesh.instances.length - partStart];
  mesh.instances.invalidate();
  if(mesh.box !is null) mesh.box.dirty = true;
}

/** Build the L-system part: run the turtle and append grouped instances + ranges. */
private void doLBrush(ref Feature f, ref immutable FeatureT ft, ref Geometry[string] meshes, float[3] wp) {
  TurtleConfig cfg;
  cfg.angle = ft.lsystemAngle;
  foreach(ref br; ft.brushes) {
    auto brt = br.resourceType == "None" ? ResourceType.None : br.resourceType.to!ResourceType;
    cfg.brush[br.symbol] = TurtleBrush(cast(int)brt, br.radius, br.length, br.advance);
  }
  char[] preds; string[] prods; uint[] probs;
  foreach(ref r; ft.rules) { preds ~= r.predecessor; prods ~= r.production; probs ~= r.probability; }
  auto str = buildGrammar(f.hash, f.height, ft.axiom, preds, prods, probs);
  char[] chars; foreach(s; str) chars ~= s.symbol;
  float[4] q0 = [0.0f, 0.0f, 0.0f, 1.0f];
  float baseY = ft.brushes[0].length * 0.5f;
  auto grouped = interpret(chars, cfg, [wp[0], wp[1] - baseY, wp[2]], q0);
  foreach(sym, insts; grouped) {
    string meshKey = ft.name ~ ":" ~ brushMesh(ft, sym);
    if(auto mp = meshKey in meshes) {
      if(*mp !is null) {
        f.instanceRuns ~= [(*mp).instances.length, insts.length];
        (*mp).instances ~= insts[];
        (*mp).instances.invalidate();
      }
    }
  }
}

Feature[] addFeatureInstances(ref GameApp app, Feature[] features, ref immutable FeatureT ft, ref Geometry[string] meshes) {
  foreach(ref f; features) {
    auto wp = app.world.tileToWorld(f.rootTile);
    float th = app.world.tileHeight;
    f.instanceRuns = [];
    foreach(ref part; ft.parts){ doPart(app, f, ft, part, meshes, wp, th); }
    if(ft.brushes.length){ doLBrush(f, ft, meshes, wp); }
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
  foreach(ref mesh; app.world.featureMeshes.values){ mesh.instances.invalidate(); if(mesh.box !is null) mesh.box.dirty = true; }
}

void removeAllFeatures(ref GameApp app, int[3] coord) {
  if(coord !in app.world.featuresModified) {
    foreach(ref ft; features) { 
      if(auto p = coord in app.world.features[ft.name]) { if((*p).length > 0){ app.world.features[ft.name].remove(coord); } }
    }
  }
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
