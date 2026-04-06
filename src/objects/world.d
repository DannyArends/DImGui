/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import tileatlas : tileUV, heightToTile, TileType, TileAtlas;
import noise : fbm;
import geometry : Geometry, position, texture, deAllocate, computeNormals;
import textures : mapTextures;

enum CHUNK_SIZE = 12;
enum CHUNK_HEIGHT = 32;

@nogc pure TileType worldTile(int wx, int wy, int wz, int seed = 0) nothrow {
  float h = fbm(wx * 0.05f, wz * 0.05f, 0.0f, 4, 2.0f, 0.5f, seed);
  int surface = cast(int)(h * CHUNK_HEIGHT);
  if (wy > surface) return TileType.None;
  if (wy == surface) return heightToTile(h);
  if (wy == 0) return TileType.Lava;
  return TileType.Stone;
}

struct Chunk {
  int[3] coord;
  Geometry geometry;
  alias geometry this;
}

void writeTile(ref Chunk chunk, const ref TileAtlas ta, float wx, float wy, float wz, TileType tile, float tileSize, float tileHeight) {
  float hs = tileSize * 0.5f;
  float[2] uvTR = ta.tileUV(tile.name, true,  false);
  float[2] uvBR = ta.tileUV(tile.name, true,  true);
  float[2] uvBL = ta.tileUV(tile.name, false, true);
  float[2] uvTL = ta.tileUV(tile.name, false, false);

  uint vi = cast(uint)chunk.geometry.vertices.length;
  uint ii = cast(uint)chunk.geometry.indices.length;

  chunk.geometry.vertices ~= [
    Vertex([wx+hs, wy, wz-hs], uvTR, [1.0f, 1.0f, 1.0f, 1.0f]),
    Vertex([wx-hs, wy, wz-hs], uvTL, [1.0f, 1.0f, 1.0f, 1.0f]),
    Vertex([wx-hs, wy, wz+hs], uvBL, [1.0f, 1.0f, 1.0f, 1.0f]),
    Vertex([wx+hs, wy, wz+hs], uvBR, [1.0f, 1.0f, 1.0f, 1.0f]),
  ];
  chunk.geometry.indices ~= [vi+0, vi+2, vi+1, vi+0, vi+3, vi+2];
}

Chunk generateChunk(ref App app, int cx, int cy, int cz, float tileSize = 1.0f, float tileHeight = 0.2f, int seed = 0) {
  Chunk chunk;
  chunk.coord = [cx, cy, cz];
  chunk.geometry = new Geometry();

  for (int z = 0; z < CHUNK_SIZE; z++) {
    for (int y = 0; y < CHUNK_HEIGHT; y++) {
      for (int x = 0; x < CHUNK_SIZE; x++) {
        int wx = cx * CHUNK_SIZE + x;
        int wy = cy * CHUNK_HEIGHT + y;
        int wz = cz * CHUNK_SIZE + z;
        TileType tile = worldTile(wx, wy, wz, seed);
        if (tile == TileType.None) continue;
        float px = wx * tileSize;
        float py = wy * tileHeight;
        float pz = wz * tileSize;
        chunk.writeTile(app.tileAtlas, px, py, pz, tile, tileSize, tileHeight);
      }
    }
  }

  if (chunk.geometry.vertices.length == 0) return chunk;  // empty chunk

  chunk.geometry.instances = [Instance()];
  chunk.geometry.meshes["Chunk"] = Mesh([0, cast(uint)chunk.geometry.vertices.length]);
  chunk.geometry.name = (){ return "Chunk"; };
  app.objects ~= chunk.geometry;
  app.objects[($-1)].texture("3DTextures");
  app.objects[($-1)].computeNormals(true);
  app.objects[($-1)].position([0.0f, -6.0f, 0.0f]);
  app.mapTextures(app.objects[($-1)]);
  return chunk;
}

struct World {
  Chunk[int[3]] chunks;
  int seed = 12345;
  int renderDistance = 4;
  float tileSize = 1.0f;
  float tileHeight = 0.2f;

  void update(ref App app, float[3] playerPos) {
    int[3] pc = [ cast(int)(floor(playerPos[0] / (CHUNK_SIZE * tileSize))),0, cast(int)(floor(playerPos[2] / (CHUNK_SIZE * tileSize))) ];

    // Load new chunks within render distance
    for (int cz = pc[2]- renderDistance; cz <= pc[2]+ renderDistance; cz++) {
      for (int cx = pc[0]- renderDistance; cx <= pc[0]+ renderDistance; cx++) {
        int[3] coord = [cx, 0, cz];
        if (coord !in chunks) {
          chunks[coord] = app.generateChunk(cx, 0, cz, tileSize, tileHeight, seed);
        }
      }
    }

    // Evict chunks outside render distance
    foreach (coord; chunks.keys) {
      if (abs(coord[0] - pc[0]) >  renderDistance || abs(coord[2] - pc[2]) >  renderDistance) {
        auto g = chunks[coord].geometry;
        if (g !is null && g.isBuffered()) {
          Geometry[] remaining;
          foreach (obj; app.objects.array) if (obj !is g) remaining ~= obj;
          app.objects.array = remaining;
          app.deAllocate(g);
        }
        chunks.remove(coord);
      }
    }
  }
}