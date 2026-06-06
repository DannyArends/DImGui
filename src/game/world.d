/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : loadBlocks, saveBlocks;
import dwarf : saveDwarfs;
import feature : Feature, removeAllFeatures, addFeatureInstances, initFeatureMeshes;
import inventory : deriveInventory;
import io : ensureWorldDir, readFile, writeFile, fixPath;
import jobs : jobQueue;
import pathfinding : invalidatePaths, repathTo;
import serialization : WORLD_MAGIC;
import tile : tileBelow, getTile, isStandable, isPassable;
import vector : sqDist, vAdd, vMul, x, y, z;
import vegetation : saveVegetation, loadVegetation;

/** World configuration and coordinate system settings, safe to send to worker threads as immutable */
struct WorldData {
  int[3] seed        = [42, 67, 69];              /// [height seed, tile seed]
  int renderDistance =  4;                        /// Render distance used to load / evict chunks
  float tileSize     =  1.0f;                     /// Size (X & Z) of a tile
  float tileHeight   =  1.0f;                     /// Y-spacing between tiles
  int chunkSize      =  isAndroid ? 32 : 64;      /// Number of tiles (X & Z) in a chunk
  int chunkHeight    =  64;                       /// Number of tiles (Y) in a chunk
  float yOffset      = -20.0f;                    /// Global world Y-offset
  uint[ResourceType.max + 1] resources;
  ResourceType[uint][int[3]] diffs;
  float[int[3]] tilePenalties;

  /** Returns the filesystem path for the world TileDiffs difference */
  const(char)* worldPath() const { return toStringz(fixPath(format("data/world/%d_%d_%d.bin", seed[0], seed[1], seed[2]))); }
  const(char)* blocksPath() const { return toStringz(fixPath(format("data/world/%d_%d_%d_drops.bin", seed[0], seed[1], seed[2]))); }
  const(char)* dwarfsPath() const { return toStringz(fixPath(format("data/world/%d_%d_%d_dwarfs.bin", seed[0], seed[1], seed[2]))); }
  const(char)* featurePath(string name) const { return toStringz(fixPath(format("data/world/%d_%d_%d_%s.bin", seed[0], seed[1], seed[2], name))); }

  /** Convert a world tile coordinate to its local coordinate within its chunk */
  @nogc pure int [3] localCoord(int[3] tile) const nothrow {
    auto coord = chunkCoord(tile);
    return [tile.x - coord.x * chunkSize, tile.y, tile.z - coord.z * chunkSize];
  }

  /** Get tile neighbours */
  @nogc pure int[3][6] tileNeighbours(const int[3] wc) const nothrow {
    return [
      [wc[0]+1, wc[1], wc[2]], [wc[0]-1, wc[1], wc[2]],
      [wc[0], wc[1]+1, wc[2]], [wc[0], wc[1]-1, wc[2]],
      [wc[0], wc[1], wc[2]+1], [wc[0], wc[1], wc[2]-1]
    ];
  }

  /** Convert a world tile coordinate to its chunk coordinate */
  @property @nogc pure int tileCount() const nothrow { return chunkSize * chunkHeight * chunkSize; }
  @property @nogc pure float chunkWorldSize() const nothrow { return chunkSize * tileSize; }
  /** Convert a chunk coordinate and local tile coordinate to a world tile coordinate */
  @nogc pure int[3] chunkCoord(int[3] tile) const nothrow { 
    return [cast(int)floor(tile[0] / cast(float)chunkSize), 0, cast(int)floor(tile[2] / cast(float)chunkSize)]; 
  }
  @property @nogc pure float blockSize() const nothrow { return(tileSize * 0.25f); }
  @property @nogc pure float blockOffset() const nothrow { return(tileHeight - blockSize) * 0.5f; }
  @property @nogc pure float radius() const nothrow { return renderDistance * chunkWorldSize * 1.41422f; }
  @property @nogc pure float height() const nothrow { return chunkHeight * tileHeight; }
  /** Convert a world coordinate to a world-space float position */
  @nogc pure float[3] worldPos(int[3] wc) const nothrow { return [wc.x * tileSize, wc.y * tileHeight, wc.z * tileSize]; }
  /** Convert a chunk coordinate and local tile coordinate to a world tile coordinate */
  @nogc pure int[3] worldCoord(int[3] coord, int[3] local) const nothrow { return coord.vMul([chunkSize, chunkHeight, chunkSize]).vAdd(local); }
}

/** Runtime world state: loaded chunks, pending loads, selection and highlight (main thread only) */
struct World {
  WorldData data;                                           /// Immutable world Data
  Chunk[int[3]] chunks;                                     /// Current chunks
  bool[int[3]] pendingChunks;                               /// Chunks generated async
  Geometry[string] featureMeshes;                           /// meshes keyed by mesh name
  Feature[][int[3]][string] features;                       /// features[featureName][chunkCoord]
  Feature[][int[3]][string] pendingFeatures;                /// pending features
  Block[uint] blocks;                                       /// Block registry
  uint blockNextID = 1;                                     /// next block ID
  Geometry[string] dropMeshes;                              /// registered drop meshes
  Inventory inventory;                                      /// Inventory
  Dwarves dwarves;                                          /// Dwarves
  PathMarkers pathMarkers;                                  /// Path markers
  int[3][] pendingUnsettle;                                 /// Blocks that need to be checked if they might
  int[3][] pendingBuildTiles;                               /// Built tiles awaiting chunk rebuild
  int[3][] pendingMineTiles;                                /// Mined tiles awaiting chunk rebuild
  PathRequest[] pendingPaths;                               /// Pending pathfinding requests
  alias data this;

  /** Mark all chunks for deallocation and clear the chunk and pending maps */
  void deallocateChunk(int[3] coord) {
    chunks[coord].tiles.deAllocate = true;
    chunks[coord].deAllocate = true;
  }

  void clear() {
    foreach (coord; chunks.keys) { if (chunks[coord] !is null) { deallocateChunk(coord); } }
    chunks.clear();
    pendingChunks.clear();
  }

  void deleteWorld(ref GameApp app) {
    SDL_RemovePath(worldPath());
    SDL_RemovePath(blocksPath());
    data.diffs = null;
    app.world.inventory.type = ResourceType.None;
    if(app.verbose) SDL_Log("Deleted world at %s", worldPath());
    clear();
  }
}

TileDiff[] flattenDiffs(ref WorldData wd) {
  TileDiff[] flat;
  foreach(coord, idxMap; wd.diffs){ foreach(idx, type; idxMap){ flat ~= TileDiff(coord, idx, type); } }
  return flat;
}

void rebuildDiffs(ref WorldData wd, TileDiff[] flat) {
  wd.diffs = null;
  foreach(ref d; flat){ wd.diffs[d.coord][d.idx] = cast(ResourceType)d.type; }
}

void loadWorld(ref GameApp app) {
  ensureWorldDir();
  app.initFeatureMeshes();

  app.world.inventory.ghost = new GhostCube([app.world.tileSize, app.world.tileHeight]);
  app.objects ~= app.world.inventory.ghost;

  auto raw = readFile(app.world.worldPath());
  if(raw.length < 8) return;
  if((cast(uint[])raw)[0] != WORLD_MAGIC) { SDL_Log("loadWorld: invalid magic"); return; }
  auto diffData = raw[8 .. $];
  if(diffData.length % TileDiff.sizeof != 0) { SDL_Log("loadWorld: corrupt diffs"); return; }
  app.world.data.rebuildDiffs(cast(TileDiff[])diffData.dup);
  app.loadBlocks();
  foreach(ref ft; features) {
    if(ft.name !in app.world.pendingFeatures) app.world.pendingFeatures[ft.name] = null;
    if(ft.name !in app.world.features) app.world.features[ft.name] = null;
    app.loadVegetation!Feature(app.world.pendingFeatures[ft.name], app.world.featurePath(ft.name));
  }
  app.deriveInventory();
}

/** Save world diffs to disk */
void saveWorld(ref GameApp app) {
  auto flat = app.world.data.flattenDiffs();
  uint[2] header = [WORLD_MAGIC, cast(uint)flat.length];
  char[] raw = (cast(char*)header.ptr)[0 .. header.sizeof] ~ cast(char[])flat;
  writeFile(app.world.worldPath(), raw);
  if(app.verbose) SDL_Log("saveWorld: %d diffs", flat.length);
  app.saveBlocks();
  foreach(ref ft; features) {
    app.saveVegetation!Feature(app.world.features[ft.name], app.world.pendingFeatures[ft.name], app.world.featurePath(ft.name));
  }
  app.saveDwarfs();
}

/** Dispatch a chunk build job to the next available worker thread */
bool dispatchWorker(ref GameApp app, int[3] coord){
  foreach(tid; app.concurrency.workers.keys) {
    if (!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, coord);
      app.world.pendingChunks[coord] = true;
      if(app.verbose) SDL_Log(toStringz(format("Loading chunk: %s A-sync", coord)));
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
      if (coord !in app.world.chunks && coord !in app.world.pendingChunks) { toLoad ~= coord; }
    }
  }
  foreach (coord; toLoad.sort!((a, b) => a.sqDist(pc) < b.sqDist(pc))){ app.dispatchWorker(coord); }

  // Load pending trees onto chunks that have been loaded
  foreach(ref ft; features) {
    if(ft.name !in app.world.pendingFeatures) continue;
    foreach(coord; app.world.pendingFeatures[ft.name].keys.dup) {
      if(coord !in app.world.chunks) continue;
      if(coord !in app.world.features[ft.name]) {
        app.world.features[ft.name][coord] = app.addFeatureInstances(app.world.pendingFeatures[ft.name][coord], ft, app.world.featureMeshes);
      }
      app.world.pendingFeatures[ft.name].remove(coord);
    }
  }

  // Evict chunks outside render distance
  foreach (coord; app.world.chunks.keys.dup) {
    if (abs(coord[0] - pc[0]) > effectiveRD || abs(coord[2] - pc[2]) > effectiveRD) {
      if (app.world.chunks[coord] !is null) { app.world.deallocateChunk(coord); }
      app.world.chunks.remove(coord);
      app.removeAllFeatures(coord);
    }
  }

  // Rebuild dirty chunks
  foreach (coord; app.world.chunks.keys) {
    if (app.world.chunks[coord].dirty && coord !in app.world.pendingChunks) { app.dispatchWorker(coord); }
  }
}
