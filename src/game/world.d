/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : loadBlocks, saveBlocks, syncBlockInstances;
import clouds : saveClouds, loadClouds;
import dwarf : saveDwarfs;
import feature : Feature, removeAllFeatures, rebuildAllFeatures, addFeatureInstances, initFeatureMeshes;
import inventory : deriveInventory;
import io : ensureWorldDir, fixPath;
import lattice : chunkCoord, localCoord, worldCoord, flatten, unflatten, Diff;
import jobs : jobQueue;
import pathfinding : invalidatePaths, repathTo;
import serialization : readData, writeData;
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

  /** Returns the filesystem path for the world TileDiffs difference */
  const(char)* worldPath() const { return worldFile(""); }
  const(char)* blocksPath() const { return worldFile("_drops"); }
  const(char)* cloudsPath() const { return worldFile("_clouds"); }
  const(char)* dwarfsPath() const { return worldFile("_dwarfs"); }
  const(char)* stockpilePath() const { return worldFile("_stockpiles"); }
  const(char)* featurePath(string name) const { return worldFile("_" ~ name.toLower); }
  const(char)* waterPath() const { return worldFile("_water"); }

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
    SDL_RemovePath(dwarfsPath());
    SDL_RemovePath(blocksPath());
    SDL_RemovePath(cloudsPath());
    SDL_RemovePath(stockpilePath());
    SDL_RemovePath(waterPath());
    data.diffs = null;
    app.world.inventory.type = ResourceType.None;
    if(app.verbose) SDL_Log("Deleted world at %s", worldPath());
    clear();
  }
}

/** Compile-time guard: World satisfies the Lattice dims contract (in engine/lattice.d) */
static assert(__traits(compiles, (ref World w) { float f = w.tileSize + w.tileHeight + w.yOffset; int i = w.chunkSize + w.chunkHeight; }),
              "World must expose the Lattice dims: tileSize/tileHeight/yOffset (float), chunkSize/chunkHeight (int)");

void loadWorld(ref GameApp app) {
  ensureWorldDir();
  app.initFeatureMeshes();

  app.world.inventory.ghost = new GhostCube([app.world.tileSize, app.world.tileHeight]);
  app.objects ~= app.world.inventory.ghost;

  Diff!ResourceType[] flat;
  uint h;
  if(readData(app.world.worldPath(), flat, h)){ app.world.data.diffs = unflatten(flat); }

  app.loadBlocks();
  app.world.loadWater();
  app.world.loadClouds();
  foreach(ref ft; features) {
    if(ft.name !in app.world.vegetation.pending) app.world.vegetation.pending[ft.name] = null;
    if(ft.name !in app.world.vegetation) app.world.vegetation[ft.name] = null;
    app.loadVegetation!Feature(app.world.vegetation.pending[ft.name], app.world.featurePath(ft.name));
    foreach(coord; app.world.vegetation.pending[ft.name].keys) app.world.vegetation.modified[coord] = true;
  }
  app.world.loadStockpiles();
  app.deriveInventory();
  app.world.syncBlockInstances();
}

/** Save world diffs to disk */
void saveWorld(ref GameApp app) {
  auto flat = flatten(app.world.data.diffs);
  writeData(app.world.worldPath(), flat, cast(uint)flat.length);
  if(app.verbose) SDL_Log("saveWorld: %d diffs", flat.length);
  app.world.saveBlocks();
  app.world.saveWater();
  app.world.saveClouds();
  foreach(ref ft; features) {
    app.saveVegetation!Feature(app.world.vegetation[ft.name], app.world.vegetation.pending[ft.name], app.world.featurePath(ft.name));
  }
  app.world.saveStockpiles();
  app.saveDwarfs();
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
