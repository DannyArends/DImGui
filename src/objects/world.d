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

/** World configuration and coordinate system settings, safe to send to worker threads as immutable
 */
struct WorldData {
  int[2] seed        = [42, 67];  /// [height seed, tile seed]
  int renderDistance =   4;       /// Render distance used to load / evict chunks
  float tileSize     =   2.0f;    /// Size (X & Z) of a tile
  float tileHeight   =   2.0f;    /// Y-spacing between tiles
  int chunkSize      =  32;       /// Number of tiles (X & Z) in a chunk
  int chunkHeight    =  32;       /// Number of tiles (Y) in a chunk
  float yOffset      = -14.0f;    /// Global world Y-offset

  /** Returns the filesystem path for a chunk's binary tile data file
   */
  const(char)* chunkPath(int[3] coord) const {
    return(toStringz(fixPath(format("data/world/%d_%d/%d_%d.bin", seed[0], seed[1], coord.x, coord.z))));
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
  void saveChunk(int[3] coord, bool verbose = false) {
    if(verbose) SDL_Log(toStringz(format("saveChunk%s: %s tileTypes", coord, chunks[coord].tileTypes.length)));
    writeFile(chunkPath(coord), cast(char[])chunks[coord].tileTypes);
  }

  /** Mark all chunks for deallocation and clear the chunk and pending maps
   */
  void clear() {
    foreach (coord; chunks.keys) {
      if (chunks[coord] !is null) {
        chunks[coord].tiles.deAllocate = true;
        chunks[coord].deAllocate = true;
      }
    }
    chunks.clear();
    pendingChunks.clear();
  }

  void deleteChunks(ref App app, const(char)* path = "data/world/") {
    auto p = fixPath(path);
    foreach(entry; dir(p)) {
      if(isdir(toStringz(entry))) { deleteChunks(app, toStringz(entry)); }
      SDL_RemovePath(toStringz(entry));
    }
    SDL_RemovePath(p);
    if(app.verbose) SDL_Log("Deleted world chunks at %s", p);
    app.ensureWorldDir();
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

  /** Map required function */
  bool isTile(float[3] pos) const {
    int[3] wc = [cast(int)(pos[0] / tileSize), cast(int)((pos[1] - yOffset) / tileHeight) - 1, cast(int)(pos[2] / tileSize)];
    auto coord = chunkCoord(wc);
    TileType tt = (coord in chunks) ? chunks[coord].tileTypes[tileIndex(localCoord(wc))] : getTile(wc);
    return tileData[tt].traversable;
  }

  float cost(float[3] pos) const {
    int[3] wc = [cast(int)(pos[0] / tileSize), cast(int)((pos[1] - yOffset) / tileHeight) - 1, cast(int)(pos[2] / tileSize)];
    auto coord = chunkCoord(wc);
    TileType tt = (coord in chunks) ? chunks[coord].tileTypes[tileIndex(localCoord(wc))] : getTile(wc);
    return tileData[tt].cost;
  }

  PathNode[] getSuccessors(PathNode* parent) const {
    PathNode[] successors;
    int py = cast(int)((parent.position[1] - yOffset) / tileHeight);
    foreach(d; [0, 2]) {
      foreach(v; [-tileSize, tileSize]) {
        float[3] to = parent.position;
        to[d] += v;
        int nx = cast(int)(to[0] / tileSize);
        int nz = cast(int)(to[2] / tileSize);
        int ny = surfaceY(nx, nz);
        if(abs(ny - py) > 1) continue;  // too steep
        to[1] = (ny + 1) * tileHeight + yOffset;
        if(isTile(to)) successors ~= PathNode(parent, to, cost(to));
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
    } else {
      return false;
    }
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
      tid.send(cast(immutable(WorldData))app.world.data, cast(immutable(TileAtlas))app.tileAtlas, coord);
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
    if (abs(coord[0] - pc[0]) > effectiveRD  || abs(coord[2] - pc[2]) > effectiveRD ) {
      if (app.world.chunks[coord].dirty) app.world.saveChunk(coord, app.verbose > 0);
      if (app.world.chunks[coord] !is null) {
        app.world.chunks[coord].tiles.deAllocate = true;
        app.world.chunks[coord].deAllocate = true; 
      }
      app.world.chunks.remove(coord);
    }
  }

  // Rebuild dirty chunks
  foreach (coord; app.world.chunks.keys) {
    if (app.world.chunks[coord].dirty && coord !in app.world.pendingChunks) {
      app.world.saveChunk(coord, app.verbose > 0);
      app.dispatchWorker(coord);
      app.world.chunks[coord].dirty = false;
    }
  }
}

