/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry;
import intersection : rayAtY;
import io : writeFile, fixPath;
import noise : noiseHT;
import tileatlas : tileData, tileUV, heightToTile;
import vector : vAdd, vMul, x, y, z;

struct WorldData {
  int[2] seed        = [42, 67];  /// [height seed, tile seed]
  int renderDistance = 2;         /// Render distance used to load / evict chunks
  float tileSize     = 1.0f;      /// Size (X & Z) of a tile
  float tileHeight   = 0.2f;      /// Y-spacing between tiles
  int chunkSize      = 32;        /// Number of tiles (X & Z) in a chunk
  int chunkHeight    = 16;        /// Number of tiles (Y) in a chunk

  const(char)* chunkPath(int[3] coord) const {
    return(toStringz(fixPath(format("data/world/%d_%d/%d_%d.bin", seed[0], seed[1], coord.x, coord.z))));
  }
  int[3] localCoord(int[3] tile) const {
    auto coord = chunkCoord(tile);
    return [tile.x - coord.x * chunkSize, tile.y, tile.z - coord.z * chunkSize];
  }
  @nogc pure TileType getTile(const int[3] wc) const nothrow {
    auto ht = noiseHT(wc.x, wc.z, seed);
    int surface = cast(int)(ht[0] * (chunkHeight - 1));
    if (wc.y > surface) return TileType.None;
    if (wc.y == 0) return TileType.Lava;
    if (wc.y < surface) return TileType.Stone;
    return heightToTile(ht[0], ht[1]);
  }
  @nogc pure int tileIndex(int[3] local) const nothrow { return(local.z * chunkHeight * chunkSize + local.y * chunkSize + local.x); }
  @nogc pure int[3] tileCoord(int i) const nothrow { return [i % chunkSize, (i / chunkSize) % chunkHeight, i / (chunkSize * chunkHeight)];}
  @property pure @nogc int tileCount() const nothrow { return chunkSize * chunkHeight * chunkSize; }
  @property pure @nogc float halfTile() const nothrow { return tileSize * 0.5f; }
  @property pure @nogc float chunkWorldSize() const nothrow { return chunkSize * tileSize; }
  pure @nogc int[3] chunkCoord(int[3] tile) const nothrow { return [cast(int)floor(tile[0] / cast(float)chunkSize), 0, cast(int)floor(tile[2] / cast(float)chunkSize)]; }
  @nogc pure float[3] worldPos(int[3] wc) const nothrow { return [wc.x * tileSize, wc.y * tileHeight, wc.z * tileSize]; }
  @nogc pure int[3] worldCoord(int[3] coord, int[3] local) const nothrow { return coord.vMul([chunkSize, chunkHeight, chunkSize]).vAdd(local); }
}

struct World {
  Chunk[int[3]] chunks;                                     /// Current chunks
  bool[int[3]] pendingChunks;                               /// Chunks being generated async
  int[3] selectedTile = [int.min, int.min, int.min];        /// Currently selected Tile
  Geometry highlight = null;                                /// Highlighted tile
  float yOffset = -6.0f;                                    /// Global world Y-offset
  WorldData data;
  alias data this;

  int[3] surfaceTile(int tx, int tz) { return [tx, cast(int)(noiseHT(tx, tz, seed)[0] * (chunkHeight - 1)), tz]; }

  // Pick a tile by fixed-point iteration: project ray to estimated surface Y, refine X/Z, repeat.
  // Converges because terrain height varies smoothly — 4 iterations is sufficient.
  int[3] pickTile(float[3][2] ray) {
    float[3] p = rayAtY(ray, yOffset);
    int[3] tile;
    for(int i = 0; i < 4; i++) {
      tile = surfaceTile(cast(int)round(p[0] / tileSize), cast(int)round(p[2] / tileSize));
      p = rayAtY(ray, tile[1] * tileHeight + yOffset);
    }
    return tile;
  }

  void updateHighlight(ref App app, int[3] tile) {
    float[3] p = data.worldPos(tile);
    if(highlight is null) {
      highlight = new Outline();
      app.objects ~= highlight;
    }
    highlight.position([p.x, p.y + yOffset + 0.01f, p.z]);
    highlight.scale([tileSize, tileSize, tileSize]);
    selectedTile = tile;
  }

  void saveChunk(int[3] coord) { writeFile(chunkPath(coord), cast(char[])chunks[coord].tiles); }

  void clear(ref App app) {
    foreach (coord; chunks.keys) { if (chunks[coord] !is null) { chunks[coord].deAllocate = true; } }
    chunks.clear();
    pendingChunks.clear();
  }
}

void setTile(ref App app, int[3] tile, TileType newType) {
  int[3] coord = app.world.chunkCoord(tile);
  if(coord !in app.world.chunks) return;

  int idx = app.world.tileIndex(app.world.localCoord(tile));
  app.world.chunks[coord].tiles[idx] = newType;
  app.world.chunks[coord].dirty = true;
}

void loadChunk(ref App app, int[3] coord){
  foreach(tid; app.concurrency.workers.keys) {
    if (!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, cast(immutable(TileAtlas))app.tileAtlas, coord);
      app.world.pendingChunks[coord] = true;
      break;
    }
  }
}

void updateWorld(ref App app, float[3] lookat) {
  int[3] pc = app.world.chunkCoord([cast(int)floor(lookat[0] / app.world.tileSize), 0, cast(int)floor(lookat[2] / app.world.tileSize)]);

  // Load new chunks within render distance
  for (int cz = pc.z - app.world.renderDistance; cz <= pc.z + app.world.renderDistance; cz++) {
    for (int cx = pc.x - app.world.renderDistance; cx <= pc.x + app.world.renderDistance; cx++) {
      int[3] coord = [cx, 0, cz];
      if (coord !in app.world.chunks && coord !in app.world.pendingChunks) app.loadChunk(coord);
    }
  }

  // Evict chunks outside render distance
  foreach (coord; app.world.chunks.keys.dup) {
    if (abs(coord[0] - pc[0]) > app.world.renderDistance || abs(coord[2] - pc[2]) > app.world.renderDistance) {
      if (app.world.chunks[coord].dirty) app.world.saveChunk(coord);
      if (app.world.chunks[coord] !is null) { app.world.chunks[coord].deAllocate = true; }
      app.world.chunks.remove(coord);
    }
  }

  // Rebuild dirty chunks
  foreach (coord; app.world.chunks.keys) {
    if (app.world.chunks[coord].dirty && coord !in app.world.pendingChunks) {
      app.world.saveChunk(coord);
      app.loadChunk(coord);
      app.world.chunks[coord].dirty = false;
    }
  }
}

