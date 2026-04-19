/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : isdir, isfile, dir, readFile, writeFile, fixPath, ensureWorldDir;
import noise : noiseHT;
import tileatlas : heightToTile;
import vector : vAdd, vMul, x, y, z;
import inventory : saveInventory;
import tileatlas : tileData;
import searchnode : PathNode;

enum uint WORLD_MAGIC = 0xCA1DE4A;

struct TileDiff {
  int[3] coord;
  uint idx;
  uint type;
}

/** World configuration and coordinate system settings, safe to send to worker threads as immutable
 */
struct WorldData {
  int[2] seed        = [42, 67];  /// [height seed, tile seed]
  int renderDistance =   4;       /// Render distance used to load / evict chunks
  float tileSize     =   2.0f;    /// Size (X & Z) of a tile
  float tileHeight   =   0.5f;    /// Y-spacing between tiles
  int chunkSize      =  32;       /// Number of tiles (X & Z) in a chunk
  int chunkHeight    =  64;       /// Number of tiles (Y) in a chunk
  float yOffset      =  -8.0f;    /// Global world Y-offset
  TileDiff[] diffs;

  /** Returns the filesystem path for the world TileDiffs difference
   */
  const(char)* worldPath() const {
    return toStringz(fixPath(format("data/world/%d_%d.bin", seed[0], seed[1])));
  }

  /** Convert a world tile coordinate to its local coordinate within its chunk
   */
  int[3] localCoord(int[3] tile) const {
    auto coord = chunkCoord(tile);
    return [tile.x - coord.x * chunkSize, tile.y, tile.z - coord.z * chunkSize];
  }

  /** Get tile neighbours
   */
  @nogc pure int[3][6] tileNeighbours(const int[3] wc) const nothrow {
    return [
      [wc[0]+1, wc[1], wc[2]], [wc[0]-1, wc[1], wc[2]],
      [wc[0], wc[1]+1, wc[2]], [wc[0], wc[1]-1, wc[2]],
      [wc[0], wc[1], wc[2]+1], [wc[0], wc[1], wc[2]-1]
    ];
  }

  /** Determine the tile type at a world coordinate from noise, no chunk data required
   */
  @nogc pure TileType getTile(const int[3] wc) const nothrow {
    auto ht = noiseHT(wc.x, wc.z, seed);
    int surface = cast(int)(ht[0] * (chunkHeight - 1));
    if (wc.y > surface) return TileType.None;
    if (wc.y == 0) return TileType.Lava;
    if (wc.y < surface) return TileType.Stone;
    return heightToTile(ht[0], ht[1]);
  }

  /** Convert a local chunk index to a 3D local tile coordinate [x, y, z]
   */
  @nogc pure int tileIndex(int[3] local) const nothrow { return(local.z * chunkHeight * chunkSize + local.y * chunkSize + local.x); }

  /** Convert a world tile coordinate to its chunk coordinate
   */
  @nogc pure int[3] tileCoord(int i) const nothrow { return [i % chunkSize, (i / chunkSize) % chunkHeight, i / (chunkSize * chunkHeight)];}

  @property @nogc pure int tileCount() const nothrow { return chunkSize * chunkHeight * chunkSize; }
  @property @nogc pure float chunkWorldSize() const nothrow { return chunkSize * tileSize; }

  /** Convert a chunk coordinate and local tile coordinate to a world tile coordinate
   */
  @nogc pure int[3] chunkCoord(int[3] tile) const nothrow { 
    return [cast(int)floor(tile[0] / cast(float)chunkSize), 0, cast(int)floor(tile[2] / cast(float)chunkSize)]; 
  }

  /** Convert a world coordinate to a world-space float position
   */
  @nogc pure float[3] worldPos(int[3] wc) const nothrow { return [wc.x * tileSize, wc.y * tileHeight, wc.z * tileSize]; }

  /** Convert a chunk coordinate and local tile coordinate to a world tile coordinate
   */
  @nogc pure int[3] worldCoord(int[3] coord, int[3] local) const nothrow { return coord.vMul([chunkSize, chunkHeight, chunkSize]).vAdd(local); }
}

/** Runtime world state: loaded chunks, pending loads, selection and highlight (main thread only)
 */
struct World {
  Chunk[int[3]] chunks;                                     /// Current chunks
  bool[int[3]] pendingChunks;                               /// Chunks being generated async
  WorldData data;
  alias data this;

  /** Save chunk tile data to disk
   */
  void saveWorld(bool verbose = false) {
    uint[2] header = [WORLD_MAGIC, cast(uint)this.data.diffs.length];
    char[] raw = (cast(char*)header.ptr)[0 .. header.sizeof] ~ cast(char[])this.data.diffs;
    writeFile(worldPath(), raw);
    if(verbose) SDL_Log("saveWorld: %d diffs", this.data.diffs.length);
  }

  void loadWorld() {
    auto raw = readFile(worldPath());
    if(raw.length < 8) return;
    if((cast(uint[])raw)[0] != WORLD_MAGIC) { SDL_Log("loadWorld: invalid magic"); return; }
    auto diffData = raw[8 .. $];
    if(diffData.length % TileDiff.sizeof != 0) { SDL_Log("loadWorld: corrupt diffs"); return; }
    data.diffs = cast(TileDiff[])diffData.dup;
    SDL_Log("loadWorld: %d diffs", data.diffs.length);
  }

  /** Mark all chunks for deallocation and clear the chunk and pending maps
   */
  void deallocateChunk(int[3] coord) {
    chunks[coord].tiles.deAllocate = true;
    chunks[coord].deAllocate = true;
  }

  void clear() {
    foreach (coord; chunks.keys) { if (chunks[coord] !is null) { deallocateChunk(coord); } }
    chunks.clear();
    pendingChunks.clear();
  }

  void deleteChunks(ref App app) {
    SDL_RemovePath(worldPath());
    if(app.verbose) SDL_Log("Deleted world at %s", worldPath());
    clear();
  }

  int surfaceY(int x, int z) const {
    for(int y = chunkHeight-1; y > 0; y--) {
      int[3] wc = [x, y, z];
      auto coord = chunkCoord(wc);
      TileType tt = (coord in chunks) ? chunks[coord].tileTypes[tileIndex(localCoord(wc))] : getTile(wc);
      if(tt != TileType.None) return y;
    }
    return 0;
  }

  TileType getTileAt(int[3] tile) const {
    auto coord = chunkCoord(tile);
    return (coord in chunks) ? chunks[coord].tileTypes[tileIndex(localCoord(tile))] : getTile(tile);
  }

  /** Map required function */
  TileType tileAt(float[3] pos) const {
    int[3] wc = [cast(int)(pos[0]/tileSize), cast(int)((pos[1]-yOffset)/tileHeight)-1, cast(int)(pos[2]/tileSize)];
    auto coord = chunkCoord(wc);
    return (coord in chunks) ? chunks[coord].tileTypes[tileIndex(localCoord(wc))] : getTile(wc);
  }
  bool isTile(float[3] pos) const { return tileData[tileAt(pos)].traversable; }
  float cost(float[3] pos) const { return tileData[tileAt(pos)].cost; }

  PathNode[] getSuccessors(PathNode* parent) const {
    PathNode[] successors;
    int px = cast(int)(parent.position[0] / tileSize);
    int py = cast(int)((parent.position[1] - yOffset) / tileHeight) - 1;
    int pz = cast(int)(parent.position[2] / tileSize);

    foreach(dir; [[1,0],[-1,0],[0,1],[0,-1]]) {
      int nx = px + dir[0];
      int nz = pz + dir[1];
      foreach(dy; [-1, 0, 1]) {
        int ny = py + dy;
        TileType solid = getTileAt([nx, ny, nz]);
        TileType air = getTileAt([nx, ny+1, nz]);
        if(air == TileType.None && tileData[solid].traversable) {
          float[3] to = [nx * tileSize, (ny+1) * tileHeight + yOffset, nz * tileSize];
          successors ~= PathNode(parent, to, tileData[solid].cost);
          break;
        }
      }
    }
    return successors;
  }
}

bool canMoveTo(ref App app, float[3] pos) {
  foreach(dx; -1..2) foreach(dy; -1..2) foreach(dz; -1..2) {
    int tx = cast(int)floor((pos[0] + dx * app.world.tileSize * 0.5f) / app.world.tileSize);
    int ty = cast(int)floor((pos[1] - app.world.yOffset + dy * app.world.tileHeight * 0.5f) / app.world.tileHeight);
    int tz = cast(int)floor((pos[2] + dz * app.world.tileSize * 0.5f) / app.world.tileSize);
    if(ty < 0 || ty >= app.world.chunkHeight) continue;
    int[3] wc = [tx, ty, tz];
    auto coord = app.world.chunkCoord(wc);
    if(coord in app.world.chunks) {
      auto idx = app.world.tileIndex(app.world.localCoord(wc));
      if(app.world.chunks[coord].tileTypes[idx] != TileType.None) return false;
    } else { return false; }
  }
  return true;
}

/** Set a tile type in a chunk and mark the chunk dirty for rebuild
 */
void setTile(ref App app, int[3] tile, TileType newType = TileType.None) {
  if(app.world.getTile(tile) == TileType.Lava) return;  // cannot remove lava
  if(app.verbose) SDL_Log(toStringz(format("setTile: %s", tile)));

  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in app.world.chunks) return;

  int idx = app.world.tileIndex(app.world.localCoord(tile));
  auto mined = app.world.chunks[coord].tileTypes[idx];  // get old type
  if(newType == TileType.None && mined != TileType.None) {
    app.inventory[mined] = app.inventory.get(mined, 0) + 1;
    app.saveInventory();
  }

  app.world.chunks[coord].tileTypes[idx] = newType;
  app.world.data.diffs ~= TileDiff(coord, idx, newType);
  app.world.chunks[coord].dirty = true;

  // Mark neighbouring chunks dirty if tile is on a chunk boundary
  foreach (n; app.world.tileNeighbours(tile)) {
    int[3] nc = app.world.chunkCoord(n);
    if (nc != coord && nc in app.world.chunks) app.world.chunks[nc].dirty = true;
  }
}

/** Dispatch a chunk build job to the next available worker thread
 */
void dispatchWorker(ref App app, int[3] coord){
  foreach(tid; app.concurrency.workers.keys) {
    if (!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, coord);
      app.world.pendingChunks[coord] = true;
      if(app.verbose) SDL_Log(toStringz(format("Loading chunk: %s A-sync", coord)));
      break;
    }
  }
}

/** Load chunks within render distance, evict chunks outside it, rebuild dirty chunks
 */
void updateWorld(ref App app, float[3] lookat) {
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
  auto sqDist = (int[3] a) => (a[0]-pc[0])^^2 + (a[2]-pc[2])^^2;
  foreach (coord; toLoad.sort!((a, b) => sqDist(a) < sqDist(b))) app.dispatchWorker(coord);

  // Evict chunks outside render distance
  foreach (coord; app.world.chunks.keys.dup) {
    if (abs(coord[0] - pc[0]) > effectiveRD || abs(coord[2] - pc[2]) > effectiveRD) {
      if (app.world.chunks[coord] !is null) { app.world.deallocateChunk(coord); }
      app.world.chunks.remove(coord);
    }
  }

  // Rebuild dirty chunks (remove saveChunk call)
  foreach (coord; app.world.chunks.keys) {
    if (app.world.chunks[coord].dirty && coord !in app.world.pendingChunks) {
      app.dispatchWorker(coord);
      app.world.chunks[coord].dirty = false;
    }
  }
}

