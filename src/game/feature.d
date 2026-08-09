/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock, unsettleBlocks;
import game : GameApp;
import lattice : tileCoord, tileToWorld, worldToTile, chunkCoord, worldCoord, getOr;
import lsystem : buildGrammar;
import matrix : translateScale, position;
import noise : noiseHTT;
import resources : variantOf;
import raws : RESOURCE_COUNT;
import sfx : play;
import timing : timed;
import turtlegfx : interpret;
import vector : vAdd, manhattan;

/** One drawing-symbol -> primitive brush for an L-system part (the data half of TurtleBrush). */
struct LSystemBrushT {
  char symbol;                                  /// grammar symbol, e.g. 'Y' or 'I'
  string mesh;                                  /// mesh name: primitive ("Cylinder") or model ("watermelon")
  ubyte substance;                              /// cast(ubyte)Substance drawn (-> the substance@feature variant)
  string texture;                               /// per-instance texture for the drawn geometry
  float radius = 0.1f;                          /// local X/Z scale
  float length = 1.0f;                          /// local Y scale / segment length
  bool advance = true;                          /// move turtle forward after drawing
  float food = 0.0f;                            /// edibility of the produced substance (0 = inedible)
  bool render = true;                           /// draw on the growing feature? false = harvest-only (a drop)
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
  float lsystemYaw = 25.0f, lsystemPitch = 25.0f, lsystemRoll = 25.0f;  /// per-axis L-system turn angles
  LSystemBrushT[] brushes;                 /// single-level array, converts to immutable like parts/drops
  string axiom = "X";                      /// L-system start symbol(s)
  Rule[] rules;                            /// L-system production rules
}

struct Feature {
  int[3] rootTile;
  uint height;
  uint hash;
  size_t[2][] instanceRuns;  // [start, count) ranges across this feature's meshes

  /** True if DrawInstance index `idx` belongs to this feature (falls within one of its instance runs). */
  bool matchIndex(size_t idx) const {
    foreach(run; instanceRuns){ if(idx >= run[0] && idx < run[0] + run[1]) { return(true); } } return(false);
  }

  /** Feature height as a float, for bounding-box / picking math. */
  @property float bboxHeight() const { return cast(float)height; }
}

private string meshKey(string name, string mesh) { return name ~ ":" ~ mesh; }

/** Wrap a mesh key in a delegate — a lazy key provider for Geometry.initInstanced. */
private string delegate() nothrow captureKey(string k) { return () => k; }

/** Resolve a raw resourceType string to its enum, treating "None" as ResourceType.None. */

/** The FeatureT whose placed feature is rooted at `tile`, or null if none. */
private const(FeatureT)* featureTypeAt(ref GameApp app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  foreach(ref ft; features) {
    if(ft.name !in app.world.vegetation) continue;
    if(auto fs = coord in app.world.vegetation[ft.name]){ if((*fs).canFind!(f => f.rootTile == tile)) { return &ft; } }
  }
  return null;
}

/** Primitive mesh name bound to grammar symbol `sym` in `ft`'s brushes, or "" if unbound. */
private string brushMesh(ref immutable FeatureT ft, char sym) {
  foreach(ref br; ft.brushes){ if(br.symbol == sym){ return(br.mesh); } } return("");
}

/** Append a batch of instances to a feature mesh: record the run on f, flag buffer + cull bounds. */
private void emitInstances(ref Feature f, Geometry mesh, const(DrawInstance)[] insts) {
  if(mesh is null) return;
  f.instanceRuns ~= mesh.addInstances(insts);
  mesh.syncInstances();
}

/** Create and register one instanced primitive mesh per (feature, part/brush mesh); skips keys already built. */
void initFeatureMeshes(ref GameApp app) {
  foreach(ref ft; features) foreach(name; ft.brushes.map!(b => b.mesh)) {
    string key = ft.name ~ ":" ~ name;
    if(key in app.world.vegetation.meshes) continue;
    auto mesh = makePrimitive(name);
    if(mesh is null) continue;
    mesh.initInstanced(captureKey(key));
    app.world.vegetation.meshes[key] = mesh;
    app.objects ~= mesh;
  }
}

alias SpawnMask = bool[RESOURCE_COUNT];

/** CTFE: per-feature spawn membership mask indexed by ResourceType, parallel to `features`. */
private SpawnMask spawnMask(const FeatureT ft) pure {
  SpawnMask m;
  foreach(s; ft.spawnOn) { auto rt = (s == "None" ? ResourceType.None : s.to!ResourceType); m[rt] = true; }
  return m;
}
immutable SpawnMask[] featureSpawnMask = () {
  SpawnMask[] a; foreach(ref ft; features) a ~= spawnMask(ft); return a; 
}();

/** Scan a chunk's surface tiles for valid spawn sites of `ft`; 
 * returns one Feature per accepted tile (gated by spawn type, noise threshold, and hash). */
Feature[] buildFeatureData(immutable(WorldData) wd, int[3] coord, const ResourceType[] tileTypes, const FeatureT ft, ref const SpawnMask spawnMask) {
  Feature[] result;
  for(int i = 0; i < wd.tileCount; i++) {
    if(tileTypes[i] == ResourceType.None) continue;
    if(i + wd.chunkSize < wd.tileCount && tileTypes[i + wd.chunkSize] != ResourceType.None) continue;
    if(!spawnMask[tileTypes[i]]) continue;
    auto lc = wd.tileCoord(i);
    auto wc = wd.worldCoord(coord, lc);
    auto n = noiseHTT(wc[0], wc[2], wd.seed);  // recompute — only for surface spawn candidates
    if(n[2] < ft.noiseThreshold) continue;
    uint hash = (wc[0] * ft.hashSeed1) ^ (wc[2] * ft.hashSeed2);
    if(hash % ft.hashMod != ft.hashRem) continue;
    uint height = ft.heightMin + (ft.heightMin == ft.heightMax ? 0 : cast(uint)((n[0]+n[1]) * (ft.heightMax-ft.heightMin) * 0.5f));
    result ~= Feature([wc[0], wc[1]+1, wc[2]], height, hash);
  }
  return result;
}

/** Harvest/interaction progress rate of the feature rooted at `tile`; returns 0.25 if none is found. */
float getFeatureProgressRate(ref GameApp app, int[3] tile) {
  auto ft = app.featureTypeAt(tile); return ft ? ft.progressRate : 0.25f;
}

/** Mark a feature's tile-penalty footprint: a column for tall features (trunk part or L-system), else the root. */
private void markFootprint(ref World world, ref Feature f, ref immutable FeatureT ft) {
  if(ft.tilePenalty <= 0.0f) return;
  bool tall = ft.brushes.length > 0;
  foreach(uint h; 0 .. (tall ? f.height : 1)){
    world.data.tilePenalties[[f.rootTile[0], f.rootTile[1] + cast(int)h, f.rootTile[2]]] = ft.tilePenalty;
  }
}

/** True if this feature type drops a Food-class raw (a forageable bush). */
bool featureDropsFood(const FeatureT ft) {
  foreach(ref br; ft.brushes) { if(br.food > 0.0f) { return(true); } }
  return(false);
}

/** Nearest rooted tile of a food-dropping feature within maxTiles; noTile if none. */
int[3] findNearestFoodFeature(ref GameApp app, int[3] from, int maxTiles = 128) {
  int[3] best = noTile; float bestD = float.max;
  foreach(const ft; features) {
    if(!featureDropsFood(ft) || ft.name !in app.world.vegetation) continue;
    foreach(coord, feats; app.world.vegetation[ft.name]) {
      foreach(ref f; feats) {
        if(f.rootTile[0] == int.min) continue;                 // tombstone
        float d = manhattan(f.rootTile, from);
        if(d < bestD && d <= maxTiles) { bestD = d; best = f.rootTile; }
      }
    }
  }
  return best;
}

/** Pure per-feature instance generation (static parts + L-system brushes), keyed by mesh name. No live state. */
DrawInstance[][string] featureMeshInstances(L)(ref L lat, ref Feature f, ref immutable FeatureT ft) {
  DrawInstance[][string] out_;
  auto wp = lat.tileToWorld(f.rootTile);
  if(ft.brushes.length) {
    TurtleConfig cfg;
    cfg.yaw = ft.lsystemYaw; cfg.pitch = ft.lsystemPitch; cfg.roll = ft.lsystemRoll;
    foreach(ref br; ft.brushes) {
      if(!br.render) continue;                                     // harvest-only brush: counted on cut, never drawn
      auto brt = variantOf(cast(Substance)br.substance, ft.name.to!Source);
      cfg.brush[br.symbol] = TurtleBrush(cast(int)brt, br.radius, br.length, br.advance, resourceData(brt).color);
    }
    auto chars = buildGrammar(f.hash, f.height, ft.axiom, ft.rules);
    float groundY = wp[1] - 0.5f * lat.tileHeight;
    auto grouped = interpret(chars, cfg, [wp[0], groundY, wp[2]], [0.0f, 0.0f, 0.0f, 1.0f]);
    foreach(sym, insts; grouped) { out_[meshKey(ft.name, brushMesh(ft, sym))] ~= insts; }
  }
  return out_;
}

/** Add all DrawInstances for each feature: mark the tile-penalty footprint, build instance
    batches (static parts + L-system brushes), and emit each via emitInstances. */
Feature[] addFeatureInstances(ref GameApp app, Feature[] features, ref immutable FeatureT ft, ref Geometry[string] meshes) {
  foreach(ref f; features) {
    f.instanceRuns = [];
    auto cp = f.rootTile in app.world.instanceCache;
    if(cp is null) {
      app.world.instanceCache[f.rootTile] = featureMeshInstances(app.world, f, ft); 
      cp = f.rootTile in app.world.instanceCache;
    }
    foreach(key, insts; *cp) { if(auto mp = key in meshes){ if(*mp !is null) emitInstances(f, *mp, insts); } }
  }
  return features;
}

/** Re-lay every loaded feature's tile-penalty footprint (static hard blocks). */
void stampFeatureFootprints(ref GameApp app) {
  foreach(ref ft; features) {
    if(ft.tilePenalty <= 0.0f) continue;
    foreach(coord, ref chunkFeatures; app.world.vegetation[ft.name]) {
      if(coord !in app.world.chunks) continue;
      foreach(ref f; chunkFeatures) app.world.markFootprint(f, ft);
    }
  }
}

/** Phase: clear penalties, reset every mesh buffer, and re-add every loaded chunk's instances. */
void rebuildInstances(ref GameApp app) {
  app.world.data.tilePenalties.clear();
  foreach(ref mesh; app.world.vegetation.meshes.values) mesh.instances.reset();
  foreach(ref ft; features) {
    foreach(coord, ref chunkFeatures; app.world.vegetation[ft.name]){
      if(coord !in app.world.chunks) continue;
      chunkFeatures = app.addFeatureInstances(chunkFeatures, ft, app.world.vegetation.meshes);
    }
  }
}

/** Phase: flag every vegetation mesh buffer for GPU re-upload. */
void syncAllMeshes(ref GameApp app) {
  foreach(ref mesh; app.world.vegetation.meshes){ mesh.syncInstances(); }
}

/** Clear and regenerate every feature's instances and tile penalties across all loaded chunks. */
void rebuildAllFeatures(ref GameApp app) {
  app.timed!rebuildInstances();
  app.timed!stampFeatureFootprints();
  app.timed!syncAllMeshes();
}

/** Forget cached features for chunk `coord`, but only if it carries no player modifications. */
void removeAllFeatures(ref GameApp app, int[3] coord) {
  if(coord in app.world.vegetation.modified) return;
  foreach(ref ft; features) {
    if(coord !in app.world.vegetation[ft.name]) continue; // Skip: Feature-types not in this chunk
    foreach(f; app.world.vegetation[ft.name].getOr(coord, null)){ app.world.instanceCache.remove(f.rootTile); }
    app.world.vegetation[ft.name].remove(coord);
  }
}

/** True if a feature with the given interaction is rooted at this tile */
bool hasFeature(ref GameApp app, int[3] tile, string interaction) {
  auto ft = app.featureTypeAt(tile); return ft !is null && ft.interaction == interaction;
}

/** Remove any pending (queued, not-yet-placed) features of type `ft` rooted at `tile`. */
void dropPending(ref GameApp app, const FeatureT ft, int[3] coord, int[3] tile) {
  if(ft.name !in app.world.vegetation.pending || coord !in app.world.vegetation.pending[ft.name]) return;
  app.world.vegetation.pending[ft.name][coord] = app.world.vegetation.pending[ft.name][coord].filter!(pf => pf.rootTile != tile).array;
}

/** Harvest every feature of type `ft` rooted at `tile` (spawns drops, removes the feature). Returns true if any harvested. */
bool harvestFeatureType(ref GameApp app, const FeatureT ft, int[3] tile, int[3] coord) {
  if(ft.name !in app.world.vegetation || coord !in app.world.vegetation[ft.name]) return false;
  bool any = false;
  for(size_t i = 0; i < app.world.vegetation[ft.name][coord].length; ) {
    auto f = app.world.vegetation[ft.name][coord][i];
    if(f.rootTile != tile) { i++; continue; }
    TurtleConfig cfg;
    cfg.yaw = ft.lsystemYaw; cfg.pitch = ft.lsystemPitch; cfg.roll = ft.lsystemRoll;
    foreach(ref br; ft.brushes) {                                  // ALL brushes: harvest-only geometry needs positions too
      auto brt = variantOf(cast(Substance)br.substance, ft.name.to!Source);
      cfg.brush[br.symbol] = TurtleBrush(cast(int)brt, br.radius, br.length, br.advance, resourceData(brt).color);
    }
    auto wp = app.world.tileToWorld(tile);
    auto chars = buildGrammar(f.hash, f.height, ft.axiom, ft.rules);
    auto grouped = interpret(chars, cfg, [wp[0], wp[1] - 0.5f * app.world.tileHeight, wp[2]], [0.0f, 0.0f, 0.0f, 1.0f]);
    foreach(ref br; ft.brushes) {                                  // spawn one drop per drawn instance, at its tile
      if(br.symbol !in grouped) continue;
      auto brt = variantOf(cast(Substance)br.substance, ft.name.to!Source);
      foreach(ref inst; grouped[br.symbol]) app.spawnBlock(app.world.worldToTile(position(inst.matrix)), Item(ItemTemplate.None, brt));
    }
    app.world.instanceCache.remove(f.rootTile);   // drop cached instances for the harvested feature
    app.world.vegetation[ft.name][coord] = app.world.vegetation[ft.name][coord][0..i] ~ app.world.vegetation[ft.name][coord][i+1..$];
    app.dropPending(ft, coord, tile);
    app.world.vegetation.modified[coord] = true;
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
    app.world.unsettleBlocks(app.world.drops, tile);
    app.rebuildAllFeatures();
  }
}
