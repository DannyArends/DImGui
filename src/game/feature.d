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
import vector : vAdd;
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
  float lsystemYaw = 25.0f, lsystemPitch = 25.0f, lsystemRoll = 25.0f;  /// per-axis L-system turn angles
  LSystemBrushT[] brushes;                 /// single-level array, converts to immutable like parts/drops
  string axiom = "X";                      /// L-system start symbol(s)
  Rule[] rules;                            /// L-system production rules
}

struct Feature {
  int[3] rootTile;
  uint height;
  size_t[2][] instanceRuns;  // [start, count) ranges across this feature's meshes
  uint hash;

  /** True if DrawInstance index `idx` belongs to this feature (falls within one of its instance runs). */
  bool matchIndex(size_t idx) const {
    foreach(run; instanceRuns){ if(idx >= run[0] && idx < run[0] + run[1]) { return(true); } } return(false);
  }

  /** Feature height as a float, for bounding-box / picking math. */
  @property float bboxHeight() const { return cast(float)height; }
}


private string meshKey(string name, string mesh) { return name ~ ":" ~ mesh; }

/** Wrap a mesh key in a delegate — a lazy key provider for Geometry.initInstanced. */
private string delegate() captureKey(string k) { return () => k; }

/** Resolve a raw resourceType string to its enum, treating "None" as ResourceType.None. */
private ResourceType resType(string s) { return s == "None" ? ResourceType.None : s.to!ResourceType; }

/** Construct a primitive mesh by name, or null if unknown. */
private Geometry makePrimitive(string mesh) {
  switch(mesh) {
    case "Cylinder": return new Cylinder(0.4f, 1.0f, 12);
    case "Icosahedron": auto m = new Icosahedron(); m.computeTangents(); return m;
    case "Cone": return new Cone(0.5f, 1.0f, 12);
    case "Cube": return new Cube();
    default: return null;
  }
}

/** The FeatureT whose placed feature is rooted at `tile`, or null if none. */
private const(FeatureT)* featureTypeAt(ref GameApp app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  foreach(ref ft; features) {
    if(ft.name !in app.world.features) continue;
    if(auto fs = coord in app.world.features[ft.name]){ if((*fs).canFind!(f => f.rootTile == tile)) { return &ft; } }
  }
  return null;
}

/** Build + register one instanced primitive mesh under `key`, once. */
private void registerMesh(ref GameApp app, string key, string mesh) {
  if(key in app.world.featureMeshes) return;
  auto m = makePrimitive(mesh);
  if(m is null) return;
  m.initInstanced(captureKey(key));
  app.world.featureMeshes[key] = m;
  app.objects ~= m;
}

/** Create and register one instanced primitive mesh per (feature, part/brush mesh); skips keys already built. */
void initFeatureMeshes(ref GameApp app) {
  foreach(ref ft; features) {
    foreach(ref part; ft.parts) app.registerMesh(meshKey(ft.name, part.mesh), part.mesh);
    foreach(ref br; ft.brushes) app.registerMesh(meshKey(ft.name, br.mesh), br.mesh);
  }
}

/** Scan a chunk's surface tiles for valid spawn sites of `ft`; 
 * returns one Feature per accepted tile (gated by spawn type, noise threshold, and hash). */
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

/** Harvest/interaction progress rate of the feature rooted at `tile`; returns 0.25 if none is found. */
float getFeatureProgressRate(ref GameApp app, int[3] tile) {
  auto ft = app.featureTypeAt(tile); return ft ? ft.progressRate : 0.25f;
}

/** Primitive mesh name bound to grammar symbol `sym` in `ft`'s brushes, or "" if unbound. */
private string brushMesh(ref immutable FeatureT ft, char sym) {
  foreach(ref br; ft.brushes){ if(br.symbol == sym){ return(br.mesh); } } return("");
}

/** Append a batch of instances to a feature mesh: record the run on f, flag buffer + cull bounds. */
private void emitInstances(ref Feature f, Geometry mesh, const(DrawInstance)[] insts) {
  if(mesh is null) return;
  f.instanceRuns ~= [mesh.instances.length, insts.length];
  mesh.instances ~= insts[];
  mesh.instances.invalidate();
  if(mesh.box !is null) mesh.box.dirty = true;
}

/** Mark a feature's tile-penalty footprint: a column for tall features (trunk part or L-system), else the root. */
private void markFootprint(ref World world, ref Feature f, ref immutable FeatureT ft) {
  if(ft.tilePenalty <= 0.0f) return;
  bool tall = ft.brushes.length > 0 || ft.parts.any!(p => p.repeat);
  foreach(uint h; 0 .. (tall ? f.height : 1)){
    world.data.tilePenalties[[f.rootTile[0], f.rootTile[1] + cast(int)h, f.rootTile[2]]] = ft.tilePenalty;
  }
}

/** Add all DrawInstances for each feature: mark the tile-penalty footprint, build instance
    batches (static parts + L-system brushes), and emit each via emitInstances. */
Feature[] addFeatureInstances(ref GameApp app, Feature[] features, ref immutable FeatureT ft, ref Geometry[string] meshes) {
  foreach(ref f; features) {
    app.world.markFootprint(f, ft);
    auto wp = app.world.tileToWorld(f.rootTile);
    f.instanceRuns = [];

    // Static parts
    foreach(ref part; ft.parts) {
      auto mp = meshKey(ft.name, part.mesh) in meshes;
      if(mp is null || *mp is null) continue;
      float sx = part.scaleX + (f.hash % 10) * part.scaleXVariance;
      float sy = part.scaleY < 0 ? app.world.tileHeight : part.scaleY + (f.hash % 5) * part.scaleYVariance;
      float oy = part.offsetY < 0 ? f.height * app.world.tileHeight : part.offsetY;
      auto rt = resType(part.resourceType);
      DrawInstance[] insts;
      if(part.repeat) {
        foreach(uint h; 0 .. f.height) {
          float s = sx - h * part.taper; if(s < 0.05f) s = 0.05f;
          insts ~= DrawInstance([cast(uint)rt, cast(uint)rt], translateScale(app.world.tileToWorld(f.rootTile.vAdd([0, cast(int)h, 0])), [s, sy, s]));
        }
      } else { insts ~= DrawInstance([cast(uint)rt, cast(uint)rt], translateScale([wp[0], wp[1] + oy, wp[2]], [sx, sy, sx])); }
      emitInstances(f, *mp, insts);
    }

    // L-system brushes
    if(ft.brushes.length) {
      TurtleConfig cfg;
      cfg.yaw = ft.lsystemYaw; cfg.pitch = ft.lsystemPitch; cfg.roll = ft.lsystemRoll;
      foreach(ref br; ft.brushes) {
        auto brt = resType(br.resourceType);
        cfg.brush[br.symbol] = TurtleBrush(cast(int)brt, br.radius, br.length, br.advance, resourceData(brt).color);
      }
      auto chars = buildGrammar(f.hash, f.height, ft.axiom, ft.rules);
      float baseY = ft.brushes[0].length * 0.5f;
      auto grouped = interpret(chars, cfg, [wp[0], wp[1] - baseY, wp[2]], [0.0f, 0.0f, 0.0f, 1.0f]);
      foreach(sym, insts; grouped) { if(auto mp = meshKey(ft.name, brushMesh(ft, sym)) in meshes){ emitInstances(f, *mp, insts); } }
    }
  }
  return features;
}

/** Clear and regenerate every feature's instances and tile penalties across all loaded chunks. */
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

/** Forget cached features for chunk `coord`, but only if it carries no player modifications. */
void removeAllFeatures(ref GameApp app, int[3] coord) {
  if(coord !in app.world.featuresModified) {
    foreach(ref ft; features) { 
      if(auto p = coord in app.world.features[ft.name]) { if((*p).length > 0){ app.world.features[ft.name].remove(coord); } }
    }
  }
}

/** True if a feature with the given interaction is rooted at this tile */
bool hasFeature(ref GameApp app, int[3] tile, string interaction) {
  auto ft = app.featureTypeAt(tile); return ft !is null && ft.interaction == interaction;
}

/** Remove any pending (queued, not-yet-placed) features of type `ft` rooted at `tile`. */
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

/** Harvest every feature type rooted at `tile`; on success, unsettle blocks above and rebuild all features. */
void interactFeaturesAt(ref GameApp app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  bool any = false;
  foreach(const ft; features) any |= app.harvestFeatureType(ft, tile, coord);
  if(any) {
    app.world.unsettleBlocks(app.world.blocks, tile);
    app.rebuildAllFeatures();
  }
}
