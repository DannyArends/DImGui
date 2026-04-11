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
  float[3] bmin = [ float.max,  float.max,  float.max];
  float[3] bmax = [-float.max, -float.max, -float.max];
}

/** Renderable cube geometry for individual blocks within a chunk, not selectable
 */
class Block : Square {
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
ChunkData buildChunkData(immutable(WorldData) wd, immutable(TileAtlas) ta, TileType[] saved = null, int[3] coord) {
  ChunkData data = ChunkData(coord);
  data.tiles.length = wd.tileCount;

  // Pass 1: populate all tiles
  for (int i = 0; i < wd.tileCount; i++) {
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    data.tiles[i] = (saved.length > 0) ? saved[i] : wd.getTile(wc);
  }

  // Pass 2: generate face instances
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tiles[i] == TileType.None) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    auto neighbours = wd.tileNeighbours(wc);

    // Skip fully buried tiles
    bool buried = true;
    foreach (n; neighbours) {
      int[3] nc = wd.chunkCoord(n);
      if (nc != coord) { buried = false; break; }
      int ni = wd.tileIndex(wd.localCoord(n));
      if (ni < 0 || ni >= cast(int)data.tiles.length) { buried = false; break; }
      if (data.tiles[ni] == TileType.None) { buried = false; break; }
    }
    if (buried) continue;

    float[3] p = wd.worldPos(wc);
    float ts = wd.tileSize, th = wd.tileHeight;
    float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
    auto uvT = ta.tileUVTransform(tileData[data.tiles[i]].name);

    float[12][6] faces = [
      [  0,  0,  ts,   1,  0,  0,   0,  th,  0,   px+ts/2, py,      pz      ],  // +X right
      [  0,  0, -ts,  -1,  0,  0,   0,  th,  0,   px-ts/2, py,      pz      ],  // -X left
      [ ts,  0,   0,   0,  1,  0,   0,   0, ts,   px,      py+th/2, pz      ],  // +Y top
      [ ts,  0,   0,   0, -1,  0,   0,   0,-ts,   px,      py-th/2, pz      ],  // -Y bottom
      [-ts,  0,   0,   0,  0,  1,   0,  th,  0,   px,      py,      pz+ts/2 ],  // +Z front
      [ ts,  0,   0,   0,  0, -1,   0,  th,  0,   px,      py,      pz-ts/2 ],  // -Z back
    ];

    for (int f = 0; f < 6; f++) {
      int[3] fnc = wd.chunkCoord(neighbours[f]);
      bool faceExposed;
      if (fnc != coord) {
        faceExposed = wd.getTile(neighbours[f]) == TileType.None;
      } else {
        int ni = wd.tileIndex(wd.localCoord(neighbours[f]));
        if (ni < 0 || ni >= cast(int)data.tiles.length) { faceExposed = true; }
        else { faceExposed = data.tiles[ni] == TileType.None; }
      }
      if (!faceExposed) continue;

      Instance inst;
      inst.uvT = uvT;
      inst.matrix = Matrix([
        faces[f][0], faces[f][1], faces[f][2], 0,
        faces[f][3], faces[f][4], faces[f][5], 0,
        faces[f][6], faces[f][7], faces[f][8], 0,
        faces[f][9], faces[f][10],faces[f][11],1
      ]);
      data.tileInstances ~= inst;
      data.tileIndices ~= i;

      if (faces[f][9]  < data.bmin[0]) data.bmin[0] = faces[f][9];
      if (faces[f][10] < data.bmin[1]) data.bmin[1] = faces[f][10];
      if (faces[f][11] < data.bmin[2]) data.bmin[2] = faces[f][11];
      if (faces[f][9]  > data.bmax[0]) data.bmax[0] = faces[f][9];
      if (faces[f][10] > data.bmax[1]) data.bmax[1] = faces[f][10];
      if (faces[f][11] > data.bmax[2]) data.bmax[2] = faces[f][11];
    }
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
  SDL_Log("finalizeChunk: coord=[%d,%d] instances=%d block_class=%s", 
    data.coord[0], data.coord[2], 
    cast(int)chunk.block.instances.length,
    toStringz(chunk.block.name()));
if (chunk.block.instances.length > 0) {
  auto m = chunk.block.instances[0].matrix;
  SDL_Log("  first instance matrix[0,12,13,14]: %.2f %.2f %.2f %.2f", m[0], m[12], m[13], m[14]);
}
SDL_Log("  block vertices=%d indices=%d", chunk.block.vertices.length, chunk.block.indices.length);
  float sx = app.world.chunkWorldSize;
  float sy = app.world.chunkHeight * app.world.tileHeight;
  float cx = data.coord[0] * sx + sx * 0.5f;
  float cz = data.coord[2] * sx + sx * 0.5f;
  float cy = sy * 0.5f + app.world.yOffset;
  chunk.instances[0].matrix = translate([cx, cy, cz]).multiply(scale([sx, sy, sx]));

  chunk.block.texture("3DTextures");
  chunk.block.box = new BoundingBox();
  chunk.block.box.setDimensions(data.bmin, data.bmax);
  chunk.block.box.instances = [Instance()]; // single instance, identity matrix
  app.mapTextures(chunk.block);

  app.objects ~= chunk.block;
  app.objects ~= chunk;
  app.world.chunks[data.coord] = chunk;
  app.world.pendingChunks.remove(data.coord);
}

