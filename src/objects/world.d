/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import tileatlas : tileUV, heightToTile, TileType, TileAtlas;
import noise : fbm;
import geometry : Geometry, position, texture, deAllocate, computeNormals;
import textures : mapTextures;

@nogc pure TileType worldTile(const World world, int wx, int wy, int wz, int seed = 0) nothrow {
  float h = fbm(wx * 0.05f, wz * 0.05f, 0.0f, 4, 2.0f, 0.5f, seed);
  float t = fbm(wx * 0.1f,  wz * 0.1f,  0.0f, 4, 2.0f, 0.5f, seed + 1337); // tile variation field
  int surface = cast(int)(h * (world.chunkHeight-1));
  if (wy > surface) return TileType.None;
  if (wy == 0) return TileType.Lava;
  if (wy < surface)  return TileType.Stone;
  if (wy == surface) return heightToTile(h, t);
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

  uint vi = cast(uint)chunk.vertices.length;
  uint ii = cast(uint)chunk.indices.length;

  chunk.vertices ~= [
    Vertex([wx+hs, wy, wz-hs], uvTR, [1.0f, 1.0f, 1.0f, 1.0f]),
    Vertex([wx-hs, wy, wz-hs], uvTL, [1.0f, 1.0f, 1.0f, 1.0f]),
    Vertex([wx-hs, wy, wz+hs], uvBL, [1.0f, 1.0f, 1.0f, 1.0f]),
    Vertex([wx+hs, wy, wz+hs], uvBR, [1.0f, 1.0f, 1.0f, 1.0f]),
  ];
  chunk.indices ~= [vi+0, vi+2, vi+1, vi+0, vi+3, vi+2];
}

Chunk generateChunk(ref App app, const World world, int cx, int cy, int cz, float tileSize = 1.0f, float tileHeight = 0.2f, int seed = 0) {
  Chunk chunk;
  chunk.coord = [cx, cy, cz];
  chunk.geometry = new Geometry();

  for (int z = 0; z < world.chunkSize; z++) {
    for (int y = 0; y < world.chunkHeight; y++) {
      for (int x = 0; x < world.chunkSize; x++) {
        int wx = cx * world.chunkSize + x;
        int wy = cy * world.chunkHeight + y;
        int wz = cz * world.chunkSize + z;
        TileType tile = world.worldTile(wx, wy, wz, seed);
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
  app.objects[($-1)].isSelectable = false;
  app.objects[($-1)].position([0.0f, -6.0f, 0.0f]);
  app.mapTextures(app.objects[($-1)]);
  return chunk;
}

struct World {
  Chunk[int[3]] chunks;
  int seed = 67;
  int renderDistance = 4;
  float tileSize = 1.0f;
  float tileHeight = 0.2f;
  int chunkSize = 8;
  int chunkHeight = 16;

  void update(ref App app, float[3] playerPos) {
    int[3] pc = [ cast(int)(floor(playerPos[0] / (chunkSize * tileSize))),0, cast(int)(floor(playerPos[2] / (chunkSize * tileSize))) ];

    // Load new chunks within render distance
    for (int cz = pc[2]- renderDistance; cz <= pc[2]+ renderDistance; cz++) {
      for (int cx = pc[0]- renderDistance; cx <= pc[0]+ renderDistance; cx++) {
        int[3] coord = [cx, 0, cz];
        if (coord !in chunks) {
          chunks[coord] = app.generateChunk(this, cx, 0, cz, tileSize, tileHeight, seed);
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

  void clear(ref App app) {
    foreach (coord; chunks.keys) {
      auto g = chunks[coord].geometry;
      if (g !is null && g.isBuffered()) {
        Geometry[] remaining;
        foreach (obj; app.objects.array) if (obj !is g) remaining ~= obj;
        app.objects.array = remaining;
        app.deAllocate(g);
      }
    }
    chunks.clear();
  }
}

void showWorldwindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBegin("World", show, 0)) {
    igBeginTable("World_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

    igTableNextColumn(); igText("Seed", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(150 * app.gui.uiscale);
    int[2] seedLimits = [0, 99999];
    if(igSliderScalar("##seed", ImGuiDataType_S32, &app.world.seed, &seedLimits[0], &seedLimits[1], "%d", 0)) { app.world.clear(app); }

    igTableNextColumn(); igText("Render Distance", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(150 * app.gui.uiscale);
    int[2] rdLimits = [1, 16];
    if(igSliderScalar("##rd", ImGuiDataType_S32, &app.world.renderDistance, &rdLimits[0], &rdLimits[1], "%d", 0)) { app.world.clear(app); };

    igTableNextColumn(); igText("Tile Size", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(150 * app.gui.uiscale);
    float[2] tsLimits = [0.1f, 5.0f];
    if(igSliderScalar("##ts", ImGuiDataType_Float, &app.world.tileSize, &tsLimits[0], &tsLimits[1], "%.2f", 0)) { app.world.clear(app); };

    igTableNextColumn(); igText("Tile Height", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(150 * app.gui.uiscale);
    float[2] thLimits = [0.05f, 2.0f];
    if(igSliderScalar("##th", ImGuiDataType_Float, &app.world.tileHeight, &thLimits[0], &thLimits[1], "%.2f", 0)) { app.world.clear(app); };

    igTableNextColumn(); igText("Chunk Size", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(150 * app.gui.uiscale);
    int[2] csLimits = [4, 32];
    if(igSliderScalar("##cs", ImGuiDataType_S32, &app.world.chunkSize, &csLimits[0], &csLimits[1], "%d", 0)){ app.world.clear(app); }

    igTableNextColumn(); igText("Chunk Height", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(150 * app.gui.uiscale);
    int[2] chLimits = [2, 32];
    if(igSliderScalar("##ch", ImGuiDataType_S32, &app.world.chunkHeight, &chLimits[0], &chLimits[1], "%d", 0)){ app.world.clear(app); }

    igTableNextColumn(); igText("Chunks loaded", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igText(toStringz(format("%d", app.world.chunks.length)), ImVec2(0.0f, 0.0f));

    igEndTable();
    igEnd();
  } else { igEnd(); }
  igPopFont();
}