/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : loadBlocks, saveBlocks, syncBlockInstances, ensureBlocks;
import clouds : saveClouds, loadClouds;
import dwarf : saveDwarfs, loadDwarfs, spawnDwarf;
import feature : Feature, removeAllFeatures, rebuildAllFeatures, addFeatureInstances, initFeatureMeshes;
import inventory : deriveInventory;
import io : ensureWorldDir, fixPath;
import lattice : chunkCoord, localCoord, worldCoord, flatten, unflatten, Diff;
import jobs : jobQueue;
import pathfinding : invalidatePaths, repathTo;
import serialization : loadSections, saveSections, podSection;
import stockpile : saveStockpiles, loadStockpiles;
import tile : tileBelow, getTile, isStandable, isPassable;
import vector : sqDist, vAdd, vMul, x, y, z;
import vegetation : saveVegetation, loadVegetation;
import water : saveWater, loadWater;

/** World configuration and coordinate system settings, safe to send to worker threads as immutable */
struct WorldData {
  int[3] seed        = [42, 67, 69];              /// [height seed, tile seed]
  int renderDistance =  4;                        /// Render distance used to load / evict chunks
  float tileSize     =  1.0f;                     /// Size (X & Z) of a tile
  float tileHeight   =  1.0f;                     /// Y-spacing between tiles
  int chunkSize      =  isAndroid ? 32 : 64;      /// Number of tiles (X & Z) in a chunk
  int chunkHeight    =  64;                       /// Number of tiles (Y) in a chunk
  float yOffset      = -20.0f;                    /// Global world Y-offset
  LatticeMap!(ResourceType[uint]) diffs;
  LatticeMap!(ubyte[uint]) waterDiffs;
  LatticeMap!float tilePenalties;

  /** Build a world-data file path: data/world/<seed>_<suffix>.bin (empty suffix = the main world file). */
  private const(char)* worldFile(string suffix) const {
    return toStringz(fixPath(format("data/world/%d_%d_%d%s.bin", seed[0], seed[1], seed[2], suffix)));
  }

  /** Returns the filesystem path for the world diffs file */
  const(char)* worldPath() const { return worldFile(""); }

  /** Convert a world tile coordinate to its chunk coordinate */
  @property @nogc pure int tileCount() const nothrow { return chunkSize * chunkHeight * chunkSize; }
  @property @nogc pure float chunkWorldSize() const nothrow { return chunkSize * tileSize; }
  @property @nogc pure float blockSize() const nothrow { return(tileSize * 0.25f); }
  @property @nogc pure float blockOffset() const nothrow { return(tileHeight - blockSize) * 0.5f; }
  @property @nogc pure float radius() const nothrow { return renderDistance * chunkWorldSize * 1.41422f; }
  @property @nogc pure float height() const nothrow { return chunkHeight * tileHeight; }
  /** Convert a world coordinate to a world-space float position */
  @nogc pure float[3] worldPos(int[3] wc) const nothrow { return [wc.x * tileSize, wc.y * tileHeight, wc.z * tileSize]; }
}

/** Runtime world state: loaded chunks, pending loads, selection and highlight (main thread only) */
struct World {
  WorldData data;                                           /// Immutable world Data
  alias data this;
  ChunkField chunks;
  Vegetation vegetation;
  Drops drops;
  StockpileField stockpiles;
  Inventory inventory;                                      /// Inventory
  Dwarves dwarves;                                          /// Dwarves
  Weather weather;
  WaterTiles water;                                         /// single batched water render object
  Paths paths;

  /** Mark all chunks for deallocation and clear the chunk and pending maps */
  void deallocateChunk(const int[3] coord) {
    chunks[coord].tiles.deAllocate = true;
    chunks[coord].deAllocate = true;
  }

  void clear() {
    foreach (coord; chunks.keys) { if (chunks[coord] !is null) { deallocateChunk(coord); } }
    chunks.clear();
    chunks.pending.clear();
  }

  void deleteWorld(ref GameApp app) {
    SDL_RemovePath(worldPath());
    data.diffs = null;
    app.world.inventory.type = ResourceType.None;
    if(app.verbose) SDL_Log("Deleted world at %s", worldPath());
    clear();
  }
}

/** Compile-time guard: World satisfies the Lattice dims contract (in engine/lattice.d) */
static assert(__traits(compiles, (ref World w) { float f = w.tileSize + w.tileHeight + w.yOffset; int i = w.chunkSize + w.chunkHeight; }),
              "World must expose the Lattice dims: tileSize/tileHeight/yOffset (float), chunkSize/chunkHeight (int)");

/** Register every world-save section once. Closures capture `app`; keys are stable strings. */
void registerPersistables(ref GameApp app) {
  if(app.persistables.length > 0) return;

  app.persistables ~= podSection!(Diff!ResourceType)("diffs", () => flatten(app.world.data.diffs), (f) { app.world.data.diffs = unflatten(f); });
  app.persistables ~= podSection!(Diff!ubyte)("water", () => app.world.saveWater(), (f) { app.world.loadWater(f); });
  app.persistables ~= podSection!CloudDiff("clouds", () => app.world.saveClouds(), (f) { app.world.loadClouds(f); });
  app.persistables ~= podSection!DwarfData("dwarfs", () => app.saveDwarfs(), (f) { app.loadDwarfs(f); });
  app.persistables ~= podSection!ubyte("stock", () => app.world.saveStockpiles(), (f) { app.world.loadStockpiles(f); });
  app.persistables ~= podSection!Block("blocks", () => app.world.saveBlocks(), (f) { app.loadBlocks(f); });

  foreach(ref ftr; features) {
    auto name = ftr.name;
    app.persistables ~= Persistable(
      () => [Section("veg:" ~ name, cast(ubyte[])app.saveVegetation!Feature(app.world.vegetation[name], app.world.vegetation.pending[name]))],
      (const ubyte[][string] b) {
        if(auto p = ("veg:" ~ name) in b) {
          app.loadVegetation!Feature(app.world.vegetation.pending[name], cast(Feature[])(*p));
          foreach(coord; app.world.vegetation.pending[name].keys){ app.world.vegetation.modified[coord] = true; }
        }
      });
  }
}

void loadWorld(ref GameApp app) {
  ensureWorldDir();
  app.initFeatureMeshes();

  app.world.inventory.ghost = new GhostCube([app.world.tileSize, app.world.tileHeight]);
  app.objects ~= app.world.inventory.ghost;

  app.ensureBlocks();
  foreach(ref ft; features) {
    if(ft.name !in app.world.vegetation.pending) app.world.vegetation.pending[ft.name] = null;
    if(ft.name !in app.world.vegetation) app.world.vegetation[ft.name] = null;
  }

  app.registerPersistables();
  auto blobs = loadSections(app.world.worldPath());
  foreach(ref p; app.persistables) p.load(blobs);

  if(app.world.dwarves is null || app.world.dwarves.dwarves.length == 0) { for(int x = 0; x <= 7; x++) app.spawnDwarf(); }

  app.deriveInventory();
  app.world.syncBlockInstances();
}

/** Save world diffs to disk */
void saveWorld(ref GameApp app) {
  app.registerPersistables();
  Section[] all;
  foreach(ref p; app.persistables) all ~= p.save();
  saveSections(app.world.worldPath(), all);
  if(app.verbose) SDL_Log("saveWorld: %d sections", cast(int)all.length);
}

/** Dispatch a chunk build job to the next available worker thread */
bool dispatchWorker(ref GameApp app, int[3] coord){
  foreach(tid; app.concurrency.workers.keys) {
    if (!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, coord);
      app.world.chunks.pending[coord] = true;
      if(app.verbose) SDL_Log(cstr("Loading chunk: %s A-sync", coord));
      return(true);
    }
  }
  return(false);
}

/** Load chunks within render distance, evict chunks outside it, rebuild dirty chunks */
void updateWorld(ref GameApp app, float[3] lookat) {
  int effectiveRD = min(app.world.renderDistance, cast(int)(app.camera.nearfar[1] / app.world.chunkWorldSize));
  int[3] pc = app.world.chunkCoord([cast(int)floor(lookat[0] / app.world.tileSize), 0, cast(int)floor(lookat[2] / app.world.tileSize)]);

  // Load new chunks within render distance
  int[3][] toLoad;
  for (int cz = pc.z - effectiveRD; cz <= pc.z + effectiveRD; cz++) {
    for (int cx = pc.x - effectiveRD; cx <= pc.x + effectiveRD; cx++) {
      int[3] coord = [cx, 0, cz];
      if (coord !in app.world.chunks && coord !in app.world.chunks.pending) { toLoad ~= coord; }
    }
  }
  foreach (coord; toLoad.sort!((a, b) => a.sqDist(pc) < b.sqDist(pc))){ app.dispatchWorker(coord); }

  // Load pending trees onto chunks that have been loaded
  foreach(ref ft; features) {
    if(ft.name !in app.world.vegetation.pending) continue;
    foreach(coord; app.world.vegetation.pending[ft.name].keys.dup) {
      if(coord !in app.world.chunks) continue;
      if(coord !in app.world.vegetation[ft.name]) {
        app.world.vegetation[ft.name][coord] = app.addFeatureInstances(app.world.vegetation.pending[ft.name][coord], ft, app.world.vegetation.meshes);
      }
      app.world.vegetation.pending[ft.name].remove(coord);
    }
  }

  // Evict chunks outside render distance
  bool evicted = false;
  foreach (coord; app.world.chunks.keys.dup) {
    if (abs(coord[0] - pc[0]) > effectiveRD || abs(coord[2] - pc[2]) > effectiveRD) {
      if (app.world.chunks[coord] !is null) { app.world.deallocateChunk(coord); }
      app.world.chunks.loaded.remove(coord);
      app.removeAllFeatures(coord);
      evicted = true;
    }
  }
  if(evicted) app.rebuildAllFeatures();

  // Rebuild dirty chunks
  foreach (coord; app.world.chunks.keys) {
    if (app.world.chunks[coord].dirty && coord !in app.world.chunks.pending) { app.dispatchWorker(coord); }
  }
}
