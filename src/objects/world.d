/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry;
import io : ensureWorldDir,writeFile, fsize, readFile, fixPath;
import noise : fbm;
import textures : mapTextures;
import tileatlas : TileT, tileUV;
import vector : vAdd, vMul;

enum float NOISE_SCALE = 0.05f;

@nogc pure TileType heightToTile(float h, float t) nothrow {
  if (h < 0.05f) return TileType.Lava;
  if (h < 0.15f){ TileType[2] variants = [TileType.Stone, TileType.Gravel]; return variants[cast(uint)(t * 2) % 2]; }
  if (h < 0.25f){ TileType[2] variants = [TileType.Sand01, TileType.Sand02]; return variants[cast(uint)(t * 2) % 2]; }
  if (h < 0.35f){ TileType[3] variants = [TileType.Gravel, TileType.Sand02, TileType.Grass01]; return variants[cast(uint)(t * 3) % 3]; }
  if (h < 0.50f){ TileType[3] variants = [TileType.Grass01, TileType.Grass02, TileType.Grass03]; return variants[cast(uint)(t * 3) % 3]; }
  if (h < 0.65f){ TileType[2] variants = [TileType.Forest01, TileType.Forest02]; return variants[cast(uint)(t * 2) % 2]; }
  if (h < 0.80f) return TileType.Stone;
  if (h < 0.90f) return TileType.Ice01;
  return TileType.Snow;
}

@nogc pure float[2] noiseHT(int x, int z, const int[2] seed) nothrow {
  return [fbm(x * NOISE_SCALE, z * NOISE_SCALE, 0.0f, 4, 2.0f, 0.5f, seed[0]),
          fbm(x * NOISE_SCALE, z * NOISE_SCALE, 0.0f, 4, 2.0f, 0.5f, seed[1])];
}

@nogc pure TileType getTile(immutable(WorldData) wd, const int[3] wc) nothrow {
  auto ht = noiseHT(wc[0], wc[2], wd.seed);
  int surface = cast(int)(ht[0] * (wd.chunkHeight - 1));
  if (wc[1] > surface) return TileType.None;
  if (wc[1] == 0) return TileType.Lava;
  if (wc[1] < surface) return TileType.Stone;
  return heightToTile(ht[0], ht[1]);
}

@nogc pure int[3] worldCoord(immutable(WorldData) wd, int[3] coord, int[3] local) nothrow {
  return coord.vMul([wd.chunkSize, wd.chunkHeight, wd.chunkSize]).vAdd(local);
}

@nogc pure float[3] worldPos(immutable(WorldData) wd, int[3] wc) nothrow {
  return [wc[0] * wd.tileSize, wc[1] * wd.tileHeight, wc[2] * wd.tileSize];
}

struct ChunkData {
  int[3] coord;
  Vertex[] vertices;
  uint[] indices;
}

struct Chunk {
  int[3] coord;
  bool dirty = false;
  Geometry geometry;
  alias geometry this;
}

pure ChunkData buildChunkData(immutable(WorldData) wd, immutable(TileAtlas) ta, immutable(TileType[]) saved = null, int[3] coord) nothrow {
  ChunkData data = ChunkData(coord);
  int i = 0;
  for (int z = 0; z < wd.chunkSize; z++) {
    for (int y = 0; y < wd.chunkHeight; y++) {
      for (int x = 0; x < wd.chunkSize; x++, i++) {
        auto wc = wd.worldCoord(coord, [x,y,z]);
        TileType tile = saved ? saved[i] : wd.getTile(wc);
        if (tile == TileType.None) continue;
        float[3] p = wd.worldPos(wc);
        uint vi = cast(uint)data.vertices.length;
        data.vertices ~= [
          Vertex([p[0]+wd.halfTile, p[1], p[2]-wd.halfTile], ta.tileUV(tile.name, true,  false), [1.0f, 1.0f, 1.0f, 1.0f]),
          Vertex([p[0]-wd.halfTile, p[1], p[2]-wd.halfTile], ta.tileUV(tile.name, true,  true), [1.0f, 1.0f, 1.0f, 1.0f]),
          Vertex([p[0]-wd.halfTile, p[1], p[2]+wd.halfTile], ta.tileUV(tile.name, false, true), [1.0f, 1.0f, 1.0f, 1.0f]),
          Vertex([p[0]+wd.halfTile, p[1], p[2]+wd.halfTile], ta.tileUV(tile.name, false, false), [1.0f, 1.0f, 1.0f, 1.0f]),
        ];
        data.indices ~= [vi+0, vi+2, vi+1, vi+0, vi+3, vi+2];
      }
    }
  }
  return data;
}

void finalizeChunk(ref App app, ChunkData data) {
  if (data.vertices.length == 0) { app.world.pendingChunks.remove(data.coord); return; }
  Chunk chunk = Chunk(data.coord);
  chunk.geometry = new Geometry();
  chunk.geometry.vertices = data.vertices;
  chunk.geometry.indices  = data.indices;
  chunk.geometry.instances = [Instance()];
  chunk.geometry.meshes["Chunk"] = Mesh([0, cast(uint)chunk.geometry.vertices.length]);
  chunk.geometry.name = (){ return "Chunk"; };
  chunk.geometry.texture("3DTextures");
  chunk.geometry.computeNormals(true);
  chunk.geometry.isSelectable = false;
  chunk.geometry.position([0.0f, app.world.yOffset, 0.0f]);
  app.mapTextures(chunk.geometry);

  app.objects ~= chunk.geometry;
  app.world.chunks[data.coord] = chunk;
  app.world.pendingChunks.remove(data.coord);
}

void saveChunk(ref App app, int[3] coord) {
  TileType[] tiles;
  tiles.length = app.world.chunkSize * app.world.chunkHeight * app.world.chunkSize;
  int i = 0;
  for (int z = 0; z < app.world.chunkSize; z++) {
    for (int y = 0; y < app.world.chunkHeight; y++) {
      for (int x = 0; x < app.world.chunkSize; x++) {
        tiles[i++] = getTile(cast(immutable(WorldData))app.world.data, app.world.worldCoord([coord[0],0,coord[2]], [x,y,z]));
      }
    }
  }
  writeFile(app.world.chunkPath(coord), cast(char[])tiles);
}

TileType[] loadChunkTiles(ref App app, int[3] coord) {
  auto path = app.world.chunkPath(coord);
  if(!fsize(path, false)) return null;
  return cast(TileType[])readFile(path);
}

struct WorldData {
  int[2] seed        = [42, 67];  /// [height seed, tile seed]
  int renderDistance = 4;         /// Render distance used to load / evict chunks
  float tileSize     = 1.0f;      /// Size (X & Z) of a tile
  float tileHeight   = 0.2f;      /// Y-spacing between tiles
  int chunkSize      = 8;         /// Number of tiles (X & Z) in a chunk
  int chunkHeight    = 16;        /// Number of tiles (Y) in a chunk


  const(char)* chunkPath(int[3] coord) {
    return(toStringz(fixPath(format("data/world/%d_%d/%d_%d.bin", seed[0], seed[1], coord[0], coord[2]))));
  }
  @property pure @nogc float halfTile() const nothrow { return tileSize * 0.5f; }
  @property pure @nogc float chunkWorldSize() const nothrow { return chunkSize * tileSize; }
}

struct World {
  Chunk[int[3]] chunks;           /// Current chunks
  bool[int[3]] pendingChunks;     /// Chunks being generated async
  Geometry highlight = null;      /// Highlighted tile
  float yOffset = -6.0f;          /// Global world Y-offset
  WorldData data;
  alias data this;

  int[3] surfaceTile(int tx, int tz) { return [tx, cast(int)(noiseHT(tx, tz, seed)[0] * (chunkHeight - 1)), tz]; }

  int[3] pickTile(float[3] rayOrigin, float[3] rayDir) {
    float t  = (yOffset - rayOrigin[1]) / rayDir[1];
    float wx = rayOrigin[0] + rayDir[0] * t;
    float wz = rayOrigin[2] + rayDir[2] * t;
    int[3] tile;
    // Fixed-point iteration: project ray to estimated surface Y, refine X/Z, repeat.
    // Converges because terrain height varies smoothly — 4 iterations is sufficient.
    for(int i = 0; i < 4; i++) {
      tile = surfaceTile(cast(int)round(wx / tileSize), cast(int)round(wz / tileSize));
      float surfY = tile[1] * tileHeight + yOffset;
      t = (surfY - rayOrigin[1]) / rayDir[1];
      wx = rayOrigin[0] + rayDir[0] * t;
      wz = rayOrigin[2] + rayDir[2] * t;
    }
    return tile;
  }

  void updateHighlight(ref App app, int[3] tile) {
    float[3] p = worldPos(cast(immutable(WorldData))data, tile);

    if(highlight is null) {
      highlight = new Outline();
      app.objects ~= highlight;
    }
    highlight.position([p[0], p[1] + yOffset + 0.01f, p[2]]);
    highlight.scale([tileSize, tileSize, tileSize]);
  }

  void clear(ref App app) {
    foreach (coord; chunks.keys) { if (chunks[coord].geometry !is null) { chunks[coord].geometry.deAllocate = true; } }
    chunks.clear();
    pendingChunks.clear();
  }
}

void loadChunk(ref App app, int[3] coord){
  auto saved = app.loadChunkTiles(coord);
  foreach(tid; app.concurrency.workers.keys) {
    if (!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, cast(immutable(TileAtlas))app.tileAtlas, cast(immutable(TileType[]))saved, coord);
      app.world.pendingChunks[coord] = true;
      break;
    }
  }
}

void updateWorld(ref App app, float[3] lookat) {
  app.ensureWorldDir();
  int[3] pc = [ cast(int)(floor(lookat[0] / (app.world.chunkWorldSize))), 0, cast(int)(floor(lookat[2] / (app.world.chunkWorldSize))) ];
  // Load new chunks within render distance
  for (int cz = pc[2]- app.world.renderDistance; cz <= pc[2]+ app.world.renderDistance; cz++) {
    for (int cx = pc[0]- app.world.renderDistance; cx <= pc[0]+ app.world.renderDistance; cx++) {
      int[3] coord = [cx, 0, cz];
      if (coord !in app.world.chunks && coord !in app.world.pendingChunks) { app.loadChunk(coord); }
    }
  }
  // Evict chunks outside render distance
  foreach (coord; app.world.chunks.keys.dup) {
    if (abs(coord[0] - pc[0]) > app.world.renderDistance || abs(coord[2] - pc[2]) > app.world.renderDistance) {
      if (app.world.chunks[coord].dirty) app.saveChunk(coord);
      if (app.world.chunks[coord].geometry !is null) { app.world.chunks[coord].geometry.deAllocate = true; }
      app.world.chunks.remove(coord);
    }
  }
}

