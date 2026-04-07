/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import tileatlas : tileUV, heightToTile, TileType, TileAtlas;
import noise : fbm;
import geometry : Geometry, position, texture, deAllocate, computeNormals;
import textures : mapTextures;

@nogc pure TileType getTile(immutable(WorldData) wd, int wx, int wy, int wz, int[2] seed = [0,0]) nothrow {
  float h = fbm(wx * 0.05f, wz * 0.05f, 0.0f, 4, 2.0f, 0.5f, seed[0]);
  float t = fbm(wx * 0.05f, wz * 0.05f, 0.0f, 4, 2.0f, 0.5f, seed[1]);
  int surface = cast(int)(h * (wd.chunkHeight-1));
  if (wy > surface) return TileType.None;
  if (wy == 0) return TileType.Lava;
  if (wy < surface)  return TileType.Stone;
  if (wy == surface) return heightToTile(h, t);
  return TileType.Stone;
}

struct ChunkData {
  int[3] coord;
  Vertex[] vertices;
  uint[] indices;
}

struct Chunk {
  int[3] coord;
  Geometry geometry;
  alias geometry this;
}

ChunkData buildChunkData(immutable(WorldData) wd, immutable(TileAtlas) ta, int cx, int cy, int cz) {
  ChunkData data;
  data.coord = [cx, cy, cz];
  for (int z = 0; z < wd.chunkSize; z++) {
    for (int y = 0; y < wd.chunkHeight; y++) {
      for (int x = 0; x < wd.chunkSize; x++) {
        int wx = cx * wd.chunkSize + x;
        int wy = cy * wd.chunkHeight + y;
        int wz = cz * wd.chunkSize + z;
        TileType tile = wd.getTile(wx, wy, wz, wd.seed);
        if (tile == TileType.None) continue;
        float px = wx * wd.tileSize;
        float py = wy * wd.tileHeight;
        float pz = wz * wd.tileSize;
        float hs = wd.tileSize * 0.5f;
        float[2] uvTR = ta.tileUV(tile.name, true,  false);
        float[2] uvBR = ta.tileUV(tile.name, true,  true);
        float[2] uvBL = ta.tileUV(tile.name, false, true);
        float[2] uvTL = ta.tileUV(tile.name, false, false);
        uint vi = cast(uint)data.vertices.length;
        data.vertices ~= [
          Vertex([px+hs, py, pz-hs], uvTR, [1.0f, 1.0f, 1.0f, 1.0f]),
          Vertex([px-hs, py, pz-hs], uvTL, [1.0f, 1.0f, 1.0f, 1.0f]),
          Vertex([px-hs, py, pz+hs], uvBL, [1.0f, 1.0f, 1.0f, 1.0f]),
          Vertex([px+hs, py, pz+hs], uvBR, [1.0f, 1.0f, 1.0f, 1.0f]),
        ];
        data.indices ~= [vi+0, vi+2, vi+1, vi+0, vi+3, vi+2];
      }
    }
  }
  return data;
}

void finalizeChunk(ref App app, ChunkData data) {
  if (data.vertices.length == 0) { app.world.pendingChunks.remove(data.coord); return; }
  Chunk chunk;
  chunk.coord = data.coord;
  chunk.geometry = new Geometry();
  chunk.geometry.vertices = data.vertices;
  chunk.geometry.indices  = data.indices;
  chunk.geometry.instances = [Instance()];
  chunk.geometry.meshes["Chunk"] = Mesh([0, cast(uint)chunk.geometry.vertices.length]);
  chunk.geometry.name = (){ return "Chunk"; };
  app.objects ~= chunk.geometry;
  app.objects[($-1)].texture("3DTextures");
  app.objects[($-1)].computeNormals(true);
  app.objects[($-1)].isSelectable = false;
  app.objects[($-1)].position([0.0f, -6.0f, 0.0f]);
  app.mapTextures(app.objects[($-1)]);
  app.world.chunks[data.coord] = chunk;
  app.world.pendingChunks.remove(data.coord);
}

struct WorldData {
  int[2] seed        = [42, 67];  // [height seed, tile seed]
  int renderDistance = 4;
  float tileSize     = 1.0f;
  float tileHeight   = 0.2f;
  int chunkSize      = 8;
  int chunkHeight    = 16;
}

struct World {
  Chunk[int[3]] chunks;           /// Current chunks
  bool[int[3]]  pendingChunks;    /// Chunks being generated async
  WorldData data;
  alias data this;


  void loadChunks(ref App app, int[3] pc) {
    for (int cz = pc[2]- renderDistance; cz <= pc[2]+ renderDistance; cz++) {
      for (int cx = pc[0]- renderDistance; cx <= pc[0]+ renderDistance; cx++) {
        int[3] coord = [cx, 0, cz];
        if (coord !in chunks && coord !in pendingChunks) {
          foreach(tid; app.concurrency.workers.keys) {
            if (!app.concurrency.workers[tid]) {
              app.concurrency.workers[tid] = true;
              tid.send(cast(immutable(WorldData))data, cast(immutable(TileAtlas))app.tileAtlas, cx, 0, cz);
              pendingChunks[coord] = true;
              break;
            }
          }
        }
      }
    }
  }

  void evictChunks(ref App app, int[3] pc) {
    foreach (coord; chunks.keys.dup) {
      if (abs(coord[0] - pc[0]) > renderDistance || abs(coord[2] - pc[2]) > renderDistance) {
        if (chunks[coord].geometry !is null) { chunks[coord].geometry.deAllocate = true; }
        chunks.remove(coord);
      }
    }
  }

  void update(ref App app, float[3] playerPos) {
    int[3] pc = [ cast(int)(floor(playerPos[0] / (chunkSize * tileSize))),0, cast(int)(floor(playerPos[2] / (chunkSize * tileSize))) ];
    loadChunks(app, pc); // Load new chunks within render distance
    evictChunks(app, pc); // Evict chunks outside render distance
  }

  void clear(ref App app) {
    foreach (coord; chunks.keys) {
      if (chunks[coord].geometry !is null) { chunks[coord].geometry.deAllocate = true; }
    }
    chunks.clear();
    pendingChunks.clear();
  }
}

