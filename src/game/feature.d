/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock, unsettleBlocks;
import game : GameApp;
import intersection : intersects;
import lattice : tileCoord, tileToWorld, worldToTile, chunkCoord, worldCoord, getOr;
import lsystem : grammar;
import matrix : position, halfExtent, translation;
import noise : noiseHTT;
import resources : variantOf, rawConfig;
import sfx : play;
import timing : timed;
import turtlegfx : interpret;
import vector : manhattan;

struct Feature {
  int[3] rootTile;
  uint height;
  uint hash;
  size_t[2][] instanceRuns;  // [start, count) ranges across this feature's meshes

  /** True if DrawInstance index `idx` belongs to this feature (falls within one of its instance runs). */
  bool matchIndex(size_t idx) const {
    foreach(run; instanceRuns){ if(idx >= run[0] && idx < run[0] + run[1]) { return(true); } } return(false);
  }

  Bounds bounds; /// world-space AABB over this feature's drawn instances (picking)
}

struct Features {
  Feature[][int[3]][string] active;
  alias active this;
  Feature[][int[3]][string] pending;
  LatticeMap!bool modified;
  Geometry[string] meshes;
}

private string meshKey(string name, string mesh) { return name ~ ":" ~ mesh; }

/** The EntityT whose placed feature is rooted at `tile`, or null if none. */
private const(RawT)* featureTypeAt(ref GameApp app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  foreach(ref ft; placedTable) {
    if(ft.name !in app.world.features) continue;
    if(auto fs = coord in app.world.features[ft.name]){ if((*fs).canFind!(f => f.rootTile == tile)) { return &ft; } }
  }
  return null;
}

/** Primitive mesh name bound to grammar symbol `sym` in `ft`'s brushes, or "" if unbound. */
private string brushMesh(ref immutable RawT ft, string sym) {
  foreach(ref br; ft.brushes){ if(br.symbol == sym){ return(br.mesh); } } return("");
}

/** Append a batch of instances to a feature mesh: record the run on f, flag buffer + cull bounds. */
private void emitInstances(ref Feature f, Geometry mesh, const(DrawInstance)[] insts) {
  if(mesh is null) return;
  f.instanceRuns ~= mesh.addInstances(insts);
  foreach(ref di; insts) {
    float[3] c = [di.matrix[12], di.matrix[13], di.matrix[14]];
    float[3] e = di.matrix.halfExtent;
    f.bounds.update([c[0]-e[0], c[1]-e[1], c[2]-e[2]]);
    f.bounds.update([c[0]+e[0], c[1]+e[1], c[2]+e[2]]);
  }
  mesh.syncInstances();
}

/** Create and register one instanced primitive mesh per (feature, part/brush mesh); skips keys already built. */
void initFeatureMeshes(ref GameApp app) {
  foreach(ref ft; placedTable) foreach(name; ft.brushes.map!(b => b.mesh)) {
    string key = ft.name ~ ":" ~ name;
    if(key in app.world.features.meshes) continue;
    auto mesh = makePrimitive(name);
    if(mesh is null) continue;
    mesh.initInstanced(key);
    app.world.features.meshes[key] = mesh;
    app.objects ~= mesh;
  }
}

/** Scan a chunk's surface tiles for valid spawn sites of `ft`; 
 * returns one Feature per accepted tile (gated by spawn type, noise threshold, and hash). */
Feature[] buildFeatureData(immutable(WorldData) wd, int[3] coord, const ResourceType[] tileTypes, const RawT ft, ref const SpawnMask spawnMask) {
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
private void markFootprint(ref World world, ref Feature f, ref immutable RawT ft) {
  if(ft.tilePenalty <= 0.0f) return;
  bool tall = ft.brushes.length > 0;
  foreach(uint h; 0 .. (tall ? f.height : 1)){
    world.data.tilePenalties[[f.rootTile[0], f.rootTile[1] + cast(int)h, f.rootTile[2]]] = ft.tilePenalty;
  }
}

/** True if this feature type drops a Food-class raw (a forageable bush). */
bool featureDropsFood(const RawT ft) {
  foreach(ref br; ft.brushes) { if(br.food > 0.0f) { return(true); } }
  return(false);
}

/** Nearest rooted tile of a food-dropping feature within maxTiles; noTile if none. */
int[3] findNearestFoodFeature(ref GameApp app, int[3] from, int maxTiles = 128) {
  int[3] best = noTile; float bestD = float.max;
  foreach(const ft; featureTable) {
    if(!featureDropsFood(ft) || ft.name !in app.world.features) continue;
    foreach(coord, feats; app.world.features[ft.name]) {
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
DrawInstance[][string] featureMeshInstances(L)(ref L lat, ref Feature f, ref immutable RawT ft) {
  DrawInstance[][string] meshes;
  auto wp = lat.tileToWorld(f.rootTile);
  if(ft.brushes.length) {
    auto cfg = rawConfig(ft, true);
    auto chars = grammar(f.hash, cast(int)f.height, ft.axiom, ft.rules);
    float groundY = wp[1] - 0.5f * lat.tileHeight;
    auto grouped = interpret(chars, cfg, [wp[0], groundY, wp[2]], [0.0f, 0.0f, 0.0f, 1.0f]);
    foreach(sym, insts; grouped) { meshes[meshKey(ft.name, brushMesh(ft, sym))] ~= insts; }
  }
  return meshes;
}

/** Add all DrawInstances for each feature: mark the tile-penalty footprint, build instance
    batches (static parts + L-system brushes), and emit each via emitInstances. */
Feature[] addFeatureInstances(ref GameApp app, Feature[] features, ref immutable RawT ft, ref Geometry[string] meshes) {
  foreach(ref f; features) {
    f.instanceRuns = []; f.bounds = Bounds.init;
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
  foreach(ref ft; placedTable) {
    if(ft.tilePenalty <= 0.0f) continue;
    foreach(coord, ref chunkFeatures; app.world.features[ft.name]) {
      if(coord !in app.world.chunks) continue;
      foreach(ref f; chunkFeatures) app.world.markFootprint(f, ft);
    }
  }
}

/** Phase: clear penalties, reset every mesh buffer, and re-add every loaded chunk's instances. */
void rebuildInstances(ref GameApp app) {
  app.world.data.tilePenalties.clear();
  foreach(ref mesh; app.world.features.meshes.values) mesh.instances.reset();
  foreach(ref ft; placedTable) {
    foreach(coord, ref chunkFeatures; app.world.features[ft.name]){
      if(coord !in app.world.chunks) continue;
      chunkFeatures = app.addFeatureInstances(chunkFeatures, ft, app.world.features.meshes);
    }
  }
}

/** Phase: flag every vegetation mesh buffer for GPU re-upload. */
void syncAllMeshes(ref GameApp app) { foreach(ref mesh; app.world.features.meshes){ mesh.syncInstances(); } }

/** Clear and regenerate every feature's instances and tile penalties across all loaded chunks. */
void rebuildAllFeatures(ref GameApp app) {
  app.timed!rebuildInstances();
  app.timed!stampFeatureFootprints();
  app.timed!syncAllMeshes();
}

/** Forget cached features for chunk `coord`, but only if it carries no player modifications. */
void removeAllFeatures(ref GameApp app, int[3] coord) {
  if(coord in app.world.features.modified) return;
  foreach(ref ft; placedTable) {
    if(coord !in app.world.features[ft.name]) continue; // Skip: Feature-types not in this chunk
    foreach(f; app.world.features[ft.name].getOr(coord, null)){ app.world.instanceCache.remove(f.rootTile); }
    app.world.features[ft.name].remove(coord);
  }
}

/** True if a feature with the given interaction is rooted at this tile */
bool hasFeature(ref GameApp app, int[3] tile, string interaction) {
  auto ft = app.featureTypeAt(tile); return ft !is null && ft.interaction == interaction;
}

/** Remove any pending (queued, not-yet-placed) features of type `ft` rooted at `tile`. */
void dropPending(ref GameApp app, const RawT ft, int[3] coord, int[3] tile) {
  if(ft.name !in app.world.features.pending || coord !in app.world.features.pending[ft.name]) return;
  app.world.features.pending[ft.name][coord] = app.world.features.pending[ft.name][coord].filter!(pf => pf.rootTile != tile).array;
}

/** Harvest every feature of type `ft` rooted at `tile` (spawns drops, removes the feature). Returns true if any harvested. */
bool harvestFeatureType(ref GameApp app, const RawT ft, int[3] tile, int[3] coord) {
  if(ft.name !in app.world.features || coord !in app.world.features[ft.name]) return false;
  bool any = false;
  for(size_t i = 0; i < app.world.features[ft.name][coord].length; ) {
    auto f = app.world.features[ft.name][coord][i];
    if(f.rootTile != tile) { i++; continue; }
    auto cfg = rawConfig(ft, false);
    auto wp = app.world.tileToWorld(tile);
    auto chars = grammar(f.hash, cast(int)f.height, ft.axiom, ft.rules);
    auto grouped = interpret(chars, cfg, [wp[0], wp[1] - 0.5f * app.world.tileHeight, wp[2]], [0.0f, 0.0f, 0.0f, 1.0f]);
    foreach(ref br; ft.brushes) {                                  // spawn one drop per drawn instance, at its tile
      if(br.symbol !in grouped) continue;
      if(!br.substance) continue;
      auto brt = variantOf(br.substance, ft.name.to!Source);
      foreach(ref inst; grouped[br.symbol]){
        int hy = app.world.worldToTile(translation(inst.matrix))[1];
        app.spawnBlock([tile[0], hy < tile[1] ? tile[1] : hy, tile[2]], Item(ItemTemplate.None, brt));
      }
    }
    app.world.instanceCache.remove(f.rootTile);   // drop cached instances for the harvested feature
    app.world.features[ft.name][coord] = app.world.features[ft.name][coord][0..i] ~ app.world.features[ft.name][coord][i+1..$];
    app.dropPending(ft, coord, tile);
    app.world.features.modified[coord] = true;
    if(ft.sound.length){ app.play(ft.sound, 0.2f); }
    any = true;
  }
  return any;
}

/** Harvest every feature type rooted at `tile`; on success, unsettle blocks above and rebuild all features. */
void interactFeaturesAt(ref GameApp app, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  bool any = false;
  foreach(const ft; featureTable) any |= app.harvestFeatureType(ft, tile, coord);
  if(any) {
    app.world.unsettleBlocks(app.world.drops, tile, 0.25f);
    app.rebuildAllFeatures();
  }
}

/** Get the best vegetation hit */
bool getBestFeature(T, alias matchGeometry)(ref GameApp app, float[3][2] ray, Intersection[] hits, T[][int[3]] objects, out int[3] rootTile)
  if(is(typeof(T.init.rootTile) == int[3])) {
  Intersection best;
  foreach(ref hit; hits) {
    if(!matchGeometry(app.objects[hit.idx[0]].geometry())) continue;
    foreach(ref chunk; objects.values) foreach(ref t; chunk) {
      if(!t.matchIndex(hit.idx[1])) continue;
      auto i = ray.intersects(t.bounds.min, t.bounds.max, hit.idx[0], hit.idx[1]);
      if(i.intersects && (!best.intersects || i.tmin < best.tmin)) { best = i; rootTile = t.rootTile; }
    }
  }
  return best.intersects;
}
