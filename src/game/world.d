/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import animal : removeChunkAnimals;
import dwarf : deleteDwarf, invalidatePaths;
import events : removeGeometry;
import feature : removeAllFeatures, rebuildAllFeatures, addFeatureInstances;
import io : fixPath;
import lattice : chunkCoord, localCoord, worldCoord;
import lights : updateSun;
import jobs : jobQueue;
import persistence : loadWorld;
import text : addWorldText, ensureWorldText;
import tile : tileBelow, getTile, isStandable, isPassable;
import vector : sqDist, vAdd, vMul, x, y, z;

uint nextEntityUID = 1;    /// Global unique id for path-routable entities (dwarves, animals)

/** World configuration and coordinate system settings, safe to send to worker threads as immutable */
struct WorldData {
  int[3] seed        = [42, 67, 69];              /// [height seed, tile seed]
  int renderDistance =  isAndroid ? 6 : 5;        /// Render distance used to load / evict chunks
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
  Animals animals;                                          /// Foraging animals
  Weather weather;                                          /// Weather
  WaterTiles water;                                         /// single batched water render object
  PathMarker paths;                                         /// Path markers

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
      app.removeChunkAnimals(coord);
      evicted = true;
    }
  }
  if(evicted) app.rebuildAllFeatures();

  // Rebuild dirty chunks
  foreach (coord; app.world.chunks.keys) {
    if (app.world.chunks[coord].dirty && coord !in app.world.chunks.pending) { app.dispatchWorker(coord); }
  }
}

void regenerateWorld(ref GameApp app) {
  auto seed = app.world.data.seed;

  // 1. Release per-dwarf GPU resources (torch lights + name-label text) before dropping them
  if(app.world.dwarves !is null){ while(app.world.dwarves.dwarves.length > 0){
    app.deleteDwarf(cast(int)(app.world.dwarves.dwarves.length - 1));
  } }

  // 2. Flag every world render object for deallocation
  foreach(ref o; app.objects){ o.deAllocate = true; } app.removeGeometry();

  // 3. Chunks: flag their geometry (deallocateChunk sets deAllocate) and clear the maps
  app.world.clear();

  // 4. Remove the save file so loadWorld starts fresh
  SDL_RemovePath(app.world.worldPath());

  // 5. Reset all CPU subsystem state to defaults
  app.world.data.diffs = null;
  app.world.data.waterDiffs = null;
  app.world.dwarves = null;
  app.world.water = null;
  app.world.drops = Drops.init;
  app.world.stockpiles = StockpileField.init;
  app.world.vegetation = Vegetation.init;
  app.world.weather = Weather.init;
  app.world.paths = PathMarker.init;
  app.world.inventory = Inventory.init;
  app.worldText = WorldText.init;

  // 6. objects/persistables are rebuilt by loadWorld; ensure they start empty
  jobQueue = []; app.objects = []; app.persistables = [];

  // 7. Restore seed and rebuild
  app.world.data.seed = seed;
  app.loadWorld();
  app.updateSun();
  app.addWorldText("CalderaD", [6.0f, 4.0f, 0.0f], [90.0f, 0.0f, 0.0f]);
}
