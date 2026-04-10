/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import geometry : texture, computeBoundingBox;
import io : readFile, fsize;
import intersection : intersects;
import textures : mapTextures;
import tileatlas : tileData, tileUVTransform;
import matrix : translate, scale, multiply;
import world : setTile;

/** Holds raw tile data and instanced rendering data for a chunk
 */
struct ChunkData {
  int[3] coord;
  TileType[] tiles;
  Instance[] tileInstances;
  int[] tileIndices;
}

/** Renderable cube geometry for individual blocks within a chunk, not selectable
 */
class Block : Cube {
  this() { super(); isSelectable = false; name = (){ return "Block"; }; }
}

/** Spatial container for a chunk, selectable via its AABB, delegates rendering to Block
 */
class Chunk : Cube {
  ChunkData data;
  Geometry block;
  bool dirty = false;
  alias data this;

  this(ChunkData cd) {
    super();
    data = cd;
    indices = [];
    instances = [Instance()];
    block = new Block();
    block.instances = cd.tileInstances;
    name = (){ return "Chunk"; };
  }
}

/** Build chunk geometry data in a worker thread: generates tile instances with neighbour culling
 */
pure ChunkData buildChunkData(immutable(WorldData) wd, immutable(TileAtlas) ta, TileType[] saved = null, int[3] coord) nothrow {
  ChunkData data = ChunkData(coord);
  data.tiles.length = wd.tileCount;
  for (int i = 0; i < wd.tileCount; i++) {
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    data.tiles[i] = (saved.length > 0) ? saved[i] : wd.getTile(wc);
    if (data.tiles[i] == TileType.None) continue;

    // Skip fully buried blocks
    bool buried = true;
    foreach (n; wd.tileNeighbours(wc)) {
      int[3] nc = wd.chunkCoord(n);
      if (nc != coord) { buried = false; break; }  // always show cross-chunk faces
      if (wd.getTile(n) == TileType.None) { buried = false; break; }
    }

    float[3] p = wd.worldPos(wc);
    float ts = wd.tileSize, th = wd.tileHeight;
    Instance inst;
    inst.uvT = ta.tileUVTransform(tileData[data.tiles[i]].name);
    inst.matrix = translate([p[0], p[1] + wd.yOffset - th * 0.5f, p[2]]).multiply(scale([ts, th, ts]));
    data.tileInstances ~= inst;
    data.tileIndices ~= i;
  }
  return data;
}

/** Load saved tile types from disk for a chunk, returns empty array if file is missing or corrupt
 */
TileType[] loadChunkTiles(immutable(WorldData) wd, int[3] coord) {
  auto path = wd.chunkPath(coord);
  if(fsize(path, false) != wd.tileCount * TileType.sizeof) { SDL_RemovePath(path); return []; }
  return cast(TileType[])readFile(path);
}

/** Two-phase world pick: broad phase via chunk BBs, narrow phase per block instance, updates highlight
 */
Intersection pickWorld(ref App app, Intersection[] hits, float[3][2] ray) {
  Intersection best;
  foreach (ref hit; hits) {
    auto chunk = cast(Chunk)app.objects[hit.idx[0]];
    if (chunk is null) return best;
    for (size_t j = 0; j < chunk.block.instances.length; j++) {
      auto i = ray.intersects(chunk.block.box.bmin(j), chunk.block.box.bmax(j), hit.idx[0], j);
      if (i.intersects && (!best.intersects || i.tmin < best.tmin)) best = i;
    }
  }
  if (best.intersects) {
    auto chunk = cast(Chunk)app.objects[best.idx[0]];
    auto local = app.world.tileCoord(chunk.tileIndices[best.idx[1]]);
    auto wc = app.world.worldCoord(chunk.coord, local);
    app.setTile(wc);
  }
  return best;
}

/** Finalize a chunk on the main thread: set up GPU resources, compute chunk AABB, add to scene
 */
void finalizeChunk(ref App app, ChunkData data) {
  if (data.coord !in app.world.pendingChunks) return;
  if (data.coord in app.world.chunks) {
    app.world.chunks[data.coord].block.deAllocate = true;
    app.world.chunks[data.coord].deAllocate = true;
  }
  if (data.tileInstances.length == 0) { app.world.pendingChunks.remove(data.coord); return; }

  Chunk chunk = new Chunk(data);

  float sx = app.world.chunkWorldSize;
  float sy = app.world.chunkHeight * app.world.tileHeight;
  float cx = data.coord[0] * sx + sx * 0.5f;
  float cz = data.coord[2] * sx + sx * 0.5f;
  float cy = sy * 0.5f + app.world.yOffset;
  chunk.instances[0].matrix = translate([cx, cy, cz]).multiply(scale([sx, sy, sx]));

  chunk.block.texture("3DTextures");
  chunk.block.computeBoundingBox();
  app.mapTextures(chunk.block);

  app.objects ~= chunk.block;
  app.objects ~= chunk;
  app.world.chunks[data.coord] = chunk;
  app.world.pendingChunks.remove(data.coord);
}

