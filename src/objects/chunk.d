/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import geometry : texture;
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
  float[3][] tileBmin;
  float[3][] tileBmax;
  int[] pickIndices;
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

bool isBuried(immutable(WorldData) wd, const TileType[] tiles, int[3] wc, int[3] coord) {
  foreach (n; wd.tileNeighbours(wc)) {
    int[3] nc = wd.chunkCoord(n);
    if (nc != coord) { return false; }
    int[3] ln = wd.localCoord(n);
    if (ln[1] < 0) continue;
    if (ln[1] >= wd.chunkHeight) return false;
    int ni = wd.tileIndex(ln);
    if (ni < 0 || ni >= cast(int)tiles.length) return false;
    if (tiles[ni] == TileType.None) return false;
  }
  return true;
}

bool isFaceExposed(immutable(WorldData) wd, const TileType[] tiles, int[3] neighbour, int[3] coord) {
  if (wd.chunkCoord(neighbour) != coord) return wd.getTile(neighbour) == TileType.None;
  int[3] ln = wd.localCoord(neighbour);
  if (ln[1] < 0) return false;
  if (ln[1] >= wd.chunkHeight) return true;
  int ni = wd.tileIndex(ln);
  if (ni < 0 || ni >= cast(int)tiles.length) return true;
  return tiles[ni] == TileType.None;
}

void buildTileFaces(immutable(WorldData) wd, const TileType[] tiles, int[3] wc, int[3] coord,
                    float[4] uvT, ref Instance[] instances, ref int[] indices, int tileIdx,
                    ref float[3] bmin, ref float[3] bmax) {
  float[3] p = wd.worldPos(wc);
  float ts = wd.tileSize, th = wd.tileHeight;
  float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
  auto neighbours = wd.tileNeighbours(wc);

  float[12][6] faces = [
    [  0,  0,  ts,   1,  0,  0,   0,  th,  0,   px+ts/2, py,      pz      ],
    [  0,  0, -ts,  -1,  0,  0,   0,  th,  0,   px-ts/2, py,      pz      ],
    [ ts,  0,   0,   0,  1,  0,   0,   0, ts,   px,      py+th/2, pz      ],
    [ ts,  0,   0,   0, -1,  0,   0,   0,-ts,   px,      py-th/2, pz      ],
    [-ts,  0,   0,   0,  0,  1,   0,  th,  0,   px,      py,      pz+ts/2 ],
    [ ts,  0,   0,   0,  0, -1,   0,  th,  0,   px,      py,      pz-ts/2 ],
  ];

  for (int f = 0; f < 6; f++) {
    if (!isFaceExposed(wd, tiles, neighbours[f], coord)) continue;
    Instance inst;
    inst.uvT = uvT;
    inst.matrix = Matrix([
      faces[f][0], faces[f][1], faces[f][2], 0,
      faces[f][3], faces[f][4], faces[f][5], 0,
      faces[f][6], faces[f][7], faces[f][8], 0,
      faces[f][9], faces[f][10],faces[f][11],1
    ]);
    instances ~= inst;
    indices ~= tileIdx;

    if (faces[f][9]  < bmin[0]) bmin[0] = faces[f][9];
    if (faces[f][10] < bmin[1]) bmin[1] = faces[f][10];
    if (faces[f][11] < bmin[2]) bmin[2] = faces[f][11];
    if (faces[f][9]  > bmax[0]) bmax[0] = faces[f][9];
    if (faces[f][10] > bmax[1]) bmax[1] = faces[f][10];
    if (faces[f][11] > bmax[2]) bmax[2] = faces[f][11];
  }
}

/** Build chunk geometry data in a worker thread: generates tile instances with neighbour culling
 */
ChunkData buildChunkData(immutable(WorldData) wd, immutable(TileAtlas) ta, TileType[] saved = null, int[3] coord) {
  ChunkData data = ChunkData(coord);
  data.tiles.length = wd.tileCount;

  for (int i = 0; i < wd.tileCount; i++) {
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    data.tiles[i] = (saved.length > 0) ? saved[i] : wd.getTile(wc);
  }

  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tiles[i] == TileType.None) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    if (isBuried(wd, data.tiles, wc, coord)) continue;
    auto uvT = ta.tileUVTransform(tileData[data.tiles[i]].name);
    size_t faceStart = data.tileInstances.length;
    buildTileFaces(wd, data.tiles, wc, coord, uvT, data.tileInstances, data.tileIndices, i, data.bmin, data.bmax);
    if (data.tileInstances.length > faceStart) {
      float ts = wd.tileSize, th = wd.tileHeight;
      float[3] p = wd.worldPos(wc);
      float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
      data.tileBmin ~= [px - ts/2, py - th/2, pz - ts/2];
      data.tileBmax ~= [px + ts/2, py + th/2, pz + ts/2];
      data.pickIndices ~= i;
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
void pickWorld(ref App app, Intersection[] hits, float[3][2] ray) {
  Intersection best;
  foreach (ref hit; hits) {
    auto chunk = cast(Chunk)app.objects[hit.idx[0]];
    if (chunk is null) return;
    for (size_t j = 0; j < chunk.tileBmin.length; j++) {
      auto i = ray.intersects(chunk.tileBmin[j], chunk.tileBmax[j], hit.idx[0], j);
      if (i.intersects && (!best.intersects || i.tmin < best.tmin)) best = i;
    }
  }
  if (best.intersects) {
    auto chunk = cast(Chunk)app.objects[best.idx[0]];
    auto local = app.world.tileCoord(chunk.pickIndices[best.idx[1]]);
    auto wc = app.world.worldCoord(chunk.coord, local);
    app.setTile(wc);
  }
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
  chunk.block.box = new BoundingBox();
  chunk.block.box.setDimensions(data.bmin, data.bmax);
  chunk.block.box.instances = [Instance()]; // single instance, identity matrix
  app.mapTextures(chunk.block);

  app.objects ~= chunk.block;
  app.objects ~= chunk;
  app.world.chunks[data.coord] = chunk;
  app.world.pendingChunks.remove(data.coord);
  app.camera.isDirty = true;
}

