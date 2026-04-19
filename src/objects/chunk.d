/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import events : getHits;
import geometry : texture, bumpmap, deAllocate;
import intersection : intersects;
import textures : mapTextures, idx;
import tileatlas : tileData;
import matrix : translate, scale, multiply;
import vector : expandBounds;
import world : setTile;
import ghost: updateGhostTile;
import inventory : placeTile;

/** Holds raw tile data and instanced rendering data for a chunk
 */
struct ChunkData {
  int[3] coord;                                             /// Chunk coordinate in chunk-space
  TileType[] tileTypes;                                     /// Tile type for each tile in the chunk
  float[3][] tileBmin;                                      /// Per-tile AABB minimum (narrow-phase picking)
  float[3][] tileBmax;                                      /// Per-tile AABB maximum (narrow-phase picking)
  int[] pickIndices;                                        /// Maps pick result index back to tile index in tileTypes
  Instance[] tileInstances;                                 /// GPU instances for all visible tile faces
  int[] tileIndices;                                        /// Maps each instance back to its tile index in tileTypes
  float[3] bmin = [ float.max,  float.max,  float.max];     /// Chunk AABB minimum (broad-phase frustum culling)
  float[3] bmax = [-float.max, -float.max, -float.max];     /// Chunk AABB maximum (broad-phase frustum culling)
}

/** Renderable cube geometry for individual blocks within a chunk, not selectable
 */
class Tiles : Square {
  this(ChunkData cd) {
    super();
    isSelectable = false;
    instancedMesh = true;
    instances = cd.tileInstances;
    name = (){ return "Tiles"; };
  }
}

/** Spatial container for a chunk, selectable via its AABB, delegates rendering to Block
 */
class Chunk : Cube {
  ChunkData data;
  Geometry tiles;
  bool dirty = false;
  alias data this;

  this(ChunkData cd, WorldData wd) {
    super();
    data = cd;
    indices = [];
    float sx = wd.chunkWorldSize;
    float sy = wd.chunkHeight * wd.tileHeight;
    float cx = data.coord[0] * sx + sx * 0.5f;
    float cz = data.coord[2] * sx + sx * 0.5f;
    float cy = sy * 0.5f + wd.yOffset;
    instances = [Instance([0,0], translate([cx, cy, cz]).multiply(scale([sx, sy, sx])))];
    tiles = new Tiles(cd);
    name = (){ return "Chunk"; };
  }
}

/** Check if a face is exposed / uncovered
 * TODO: should use TileType[][int[3]] (coordinate as index) but that doesn't work on Android
 */
bool isFaceExposed(immutable(WorldData) wd, const TileType[][5] tileCache, const int[3][5] coords, int[3] neighbour, int[3] coord) {
  int[3] nc = wd.chunkCoord(neighbour);
  int ci = (nc == coord) ? 0 : cast(int)coords[1..5].countUntil(nc) + 1;
  if (ci == 0 && nc != coord) return true;  // not found in any cache
  if (ci < 0 || ci >= 5) return true;
  int[3] ln = wd.localCoord(neighbour);
  if (ln[1] < 0) return false;
  if (ln[1] >= wd.chunkHeight) return true;
  int ni = wd.tileIndex(ln);
  if (ni < 0 || ni >= cast(int)tileCache[ci].length) return true;
  return tileCache[ci][ni] == TileType.None;
}

/** Load the TileCache, 
 * TODO: should use TileType[][int[3]] (coordinate as index) but that doesn't work on Android
 */
TileType[][5] loadTileCache(immutable(WorldData) wd, int[3][5] coords, int[3] coord) {
  TileType[][5] tileCache;
  foreach (ci; 0 .. 5) {
    tileCache[ci].length = wd.tileCount;
    for (int i = 0; i < wd.tileCount; i++) { tileCache[ci][i] = wd.getTile(wd.worldCoord(coords[ci], wd.tileCoord(i))); }
    foreach (d; wd.diffs) { if (d.coord == coords[ci]) tileCache[ci][d.idx] = cast(TileType)d.type; }
  }
  return tileCache;
}

/** Build chunk geometry data in a worker thread: generates tile instances with neighbour culling
 */
ChunkData buildChunkData(immutable(WorldData) wd, int[3] coord) {
  int[3][5] coords = [coord, [coord[0]+1, 0, coord[2]], [coord[0]-1, 0, coord[2]], [coord[0], 0, coord[2]+1], [coord[0], 0, coord[2]-1]];
  TileType[][5] tileCache = wd.loadTileCache(coords, coord);

  ChunkData data = ChunkData(coord, tileCache[0]);

  float ts = wd.tileSize, th = wd.tileHeight;
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tileTypes[i] == TileType.None) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    float[3] p = wd.worldPos(wc);
    float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
    float[12][6] faces = [
      [  0,  0,  ts,   1,  0,  0,   0,  th,  0,   px+ts/2, py,      pz      ],
      [  0,  0, -ts,  -1,  0,  0,   0,  th,  0,   px-ts/2, py,      pz      ],
      [ ts,  0,   0,   0,  1,  0,   0,   0, ts,   px,      py+th/2, pz      ],
      [ ts,  0,   0,   0, -1,  0,   0,   0,-ts,   px,      py-th/2, pz      ],
      [-ts,  0,   0,   0,  0,  1,   0,  th,  0,   px,      py,      pz+ts/2 ],
      [ ts,  0,   0,   0,  0, -1,   0,  th,  0,   px,      py,      pz-ts/2 ],
    ];
    size_t faceStart = data.tileInstances.length;
    foreach (f; 0 .. 6) {
      if (!wd.isFaceExposed(tileCache, coords, wd.tileNeighbours(wc)[f], coord)) continue;
      data.tileInstances ~= Instance(cast(uint)data.tileTypes[i], faces[f]);
      data.tileIndices ~= i;
    }
    // Always expand chunk AABB with full tile extents, regardless of face culling
    expandBounds(data.bmin, data.bmax, [px - ts/2, py - th/2, pz - ts/2]);
    expandBounds(data.bmin, data.bmax, [px + ts/2, py + th/2, pz + ts/2]);
    if (data.tileInstances.length > faceStart) {
      data.tileBmin ~= [px - ts/2, py - th/2, pz - ts/2];
      data.tileBmax ~= [px + ts/2, py + th/2, pz + ts/2];
      data.pickIndices ~= i;
    }
  }
  return data;
}

/** Find the best intersecting tile in the world given a ray, returns world coord or [int.min,0,0] 
 */
bool getBestTile(ref App app, float[3][2] ray, out int[3] wc) {
  Intersection best;
  foreach (ref hit; app.getHits(ray, false)) {
    auto chunk = cast(Chunk)app.objects[hit.idx[0]];
    if (chunk is null) continue;
    for (size_t j = 0; j < chunk.tileBmin.length; j++) {
      auto i = ray.intersects(chunk.tileBmin[j], chunk.tileBmax[j], hit.idx[0], j);
      if (i.intersects && (!best.intersects || i.tmin < best.tmin)) best = i;
    }
  }
  if (!best.intersects) return false;
  auto chunk = cast(Chunk)app.objects[best.idx[0]];
  auto local = app.world.tileCoord(chunk.pickIndices[best.idx[1]]);
  wc = app.world.worldCoord(chunk.coord, local);
  return true;
}

/** Finalize a chunk on the main thread: set up GPU resources, compute chunk AABB, add to scene
 */
void finalizeChunk(ref App app, ChunkData data) {
  if (data.coord !in app.world.pendingChunks) return;
  if (data.tileInstances.length == 0) { app.world.pendingChunks.remove(data.coord); return; }

  Chunk chunk = new Chunk(data, app.world);
  chunk.tiles.box = new BoundingBox();
  chunk.tiles.box.setDimensions(data.bmin, data.bmax);

  if (data.coord in app.world.chunks) {
    auto oldTiles = app.world.chunks[data.coord].tiles;
    oldTiles.instances = chunk.tiles.instances;
    oldTiles.buffers[INSTANCE] = false;
    chunk.tiles = oldTiles;
    app.world.chunks[data.coord].deAllocate = true;
  } else { app.objects ~= chunk.tiles; }
  app.objects ~= chunk;

  app.world.chunks[data.coord] = chunk;
  app.world.pendingChunks.remove(data.coord);
  app.camera.isDirty = true;
}

