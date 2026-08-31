/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock;
import feature : dropPending;
import noise : noiseHTT;
import lattice : chunkCoord, tileCoord, tileToWorld, worldCoord, worldToTile;
import lsystem : grammar;
import matrix : translation;
import resources : variantOf, rawConfig;
import sfx : play;
import turtlegfx : interpret;
import vector : manhattan;

alias Vegetation = Features;

/** Create a tombstone entry for a cleared chunk */
T makeTombstone(T)(int[3] coord) if(is(typeof(T.init.rootTile) == int[3])) {
  T t = { rootTile: [int.min, coord[0], coord[2]] }; return(t);
}

/** Save vegetation objects to disk */
T[] saveVegetation(T)(ref GameApp app, ref T[][int[3]] objects, ref T[][int[3]] pending) if(is(typeof(T.init.rootTile) == int[3])) {
  foreach(coord, items; pending) {
    if(coord !in objects) {
      objects[coord] = items;
    }else if(objects[coord].length == 0) { objects[coord] = items; }
  }
  pending.clear();
  T[] all;
  foreach(coord, items; objects) { all ~= items.length == 0 ? [makeTombstone!T(coord)] : items; }
  return(all);
}

/** Load vegetation objects from disk into pending map */
void loadVegetation(T)(ref GameApp app, ref T[][int[3]] pending, T[] items) if(is(typeof(T.init.rootTile) == int[3])) {
  foreach(ref item; items) {
    if(item.rootTile[0] == int.min) { pending[[item.rootTile[1], 0, item.rootTile[2]]] = []; continue; }
    pending[app.world.chunkCoord(item.rootTile)] ~= item;
  }
}

/** Get a vegetation section to persit to disk */
Persist vegetationSection(ref GameApp app, string name) {
  return Persist(
    () => [Section("veg:" ~ name, cast(ubyte[])app.saveVegetation!Feature(app.world.features[name], app.world.features.pending[name]))],
    (const ubyte[][string] b) {
      if(auto p = ("veg:" ~ name) in b) {
        app.loadVegetation!Feature(app.world.features.pending[name], cast(Feature[])(*p));
        foreach(coord, items; app.world.features.pending[name]){ if(items.length > 0){ app.world.features.modified[coord] = true; } }
      }
    });
}

/** Scan a chunk's surface tiles for valid spawn sites of `ft`; 
 * returns one Feature per accepted tile (gated by spawn type, noise threshold, and hash). */
Feature[] spawnVegetation(immutable(WorldData) wd, int[3] coord, const ResourceType[] tileTypes, const RawT ft, ref const SpawnMask spawnMask) {
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

/** True if this feature type drops a Food-class raw (a forageable bush). */
bool containsFood(const RawT ft) {
  foreach(ref br; ft.brushes) { if(br.food > 0.0f) { return(true); } }
  return(false);
}

/** Nearest rooted tile of a food-dropping feature within maxTiles; noTile if none. */
int[3] findNearestFoodVegetation(ref GameApp app, int[3] from, int maxTiles = 128) {
  int[3] best = noTile; float bestD = float.max;
  foreach(const ft; featureTable) {
    if(!containsFood(ft) || ft.name !in app.world.features) continue;
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

/** Harvest every feature of type `ft` rooted at `tile` (spawns drops, removes the feature). Returns true if any harvested. */
bool harvestVegetation(ref GameApp app, const RawT ft, int[3] tile, int[3] coord) {
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