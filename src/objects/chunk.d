/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import geometry : texture, computeNormals, position;
import io : readFile, fsize;
import textures : mapTextures;
import tileatlas : tileData, tileUV, heightToTile;

struct ChunkData {
  int[3] coord;
  TileType[] tiles;
  Vertex[] vertices;
  uint[] indices;
}

class Chunk : Geometry {
  ChunkData data;
  bool dirty = false;
  alias data this;

  this(ChunkData cd) {
    data = cd;
    vertices = cd.vertices;
    indices = cd.indices;
    instances = [Instance()];
    meshes["Chunk"] = Mesh([0, cast(uint)vertices.length]);
    name = (){ return "Chunk"; };
  }
}

pure ChunkData buildChunkData(immutable(WorldData) wd, immutable(TileAtlas) ta, TileType[] saved = null, int[3] coord) nothrow {
  ChunkData data = ChunkData(coord);
  data.tiles.length = wd.tileCount;
  for (int i = 0; i < wd.tileCount; i++) {
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    data.tiles[i] = (saved.length > 0) ? saved[i] : wd.getTile(wc);
    if (data.tiles[i] == TileType.None) continue;
    float[3] p = wd.worldPos(wc);
    uint vi = cast(uint)data.vertices.length;
    string name = tileData[data.tiles[i]].name;
    data.vertices ~= [
      Vertex([p[0]+wd.halfTile, p[1], p[2]-wd.halfTile], ta.tileUV(name, true, false)),
      Vertex([p[0]-wd.halfTile, p[1], p[2]-wd.halfTile], ta.tileUV(name, true, true)),
      Vertex([p[0]-wd.halfTile, p[1], p[2]+wd.halfTile], ta.tileUV(name, false, true)),
      Vertex([p[0]+wd.halfTile, p[1], p[2]+wd.halfTile], ta.tileUV(name, false, false))
    ];
    data.indices ~= [vi+0, vi+2, vi+1, vi+0, vi+3, vi+2];
  }
  return data;
}

TileType[] loadChunkTiles(immutable(WorldData) wd, int[3] coord) {
  auto path = wd.chunkPath(coord);
  if(fsize(path, false) != wd.tileCount * TileType.sizeof) { SDL_RemovePath(path); return []; }
  return cast(TileType[])readFile(path);
}

void finalizeChunk(ref App app, ChunkData data) {
  if (data.coord !in app.world.pendingChunks) return;
  if (data.coord in app.world.chunks) { app.world.chunks[data.coord].deAllocate = true; }
  if (data.vertices.length == 0) { app.world.pendingChunks.remove(data.coord); return; }
  Geometry chunk = new Chunk(data);
  chunk.texture("3DTextures");
  chunk.computeNormals(true);
  chunk.position([0.0f, app.world.yOffset, 0.0f]);
  app.mapTextures(chunk);

  app.objects ~= chunk;
  app.world.chunks[data.coord] = cast(Chunk)(chunk);
  app.world.pendingChunks.remove(data.coord);
}
