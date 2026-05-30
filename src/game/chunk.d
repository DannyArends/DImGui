/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : unsettleBlocks;
import game : GameApp;
import gameobjects : Chunk;
import buffer : deAllocate;
import intersection : intersects;
import tile : getTile, tileIndex, tileCoord, tileToWorld, worldToTile, onChunkBoundary, isBuried;
import hits : getHits;
import noise : noiseHTT, noise2D;
import textures : idx;
import vector : expandBounds;
import feature : buildFeatureData, NoiseCache;

/** Holds raw tile data and instanced rendering data for a chunk */
struct ChunkData {
  int[3] coord;                                             /// Chunk coordinate in chunk-space
  ResourceType[] tileTypes;                                 /// Tile type for each tile in the chunk
  float[3][] tileBmin;                                      /// Per-tile AABB minimum (narrow-phase picking)
  float[3][] tileBmax;                                      /// Per-tile AABB maximum (narrow-phase picking)
  int[] pickIndices;                                        /// Maps pick result index back to tile index in tileTypes
  DrawInstance[] tileInstances;                             /// GPU instances for all visible tile faces
  int[] tileIndices;                                        /// Maps each instance back to its tile index in tileTypes
  Feature[][string] featureData;                            /// Chunk Features
  float[3] bmin = [ float.max,  float.max,  float.max];     /// Chunk AABB minimum (broad-phase frustum culling)
  float[3] bmax = [-float.max, -float.max, -float.max];     /// Chunk AABB maximum (broad-phase frustum culling)
}

/** Check if a face is exposed / uncovered */
bool isFaceExposed(immutable(WorldData) wd, const ResourceType[][5] tileCache, const int[3][5] coords, int[3] neighbour, int[3] coord) {
  int[3] nc = wd.chunkCoord(neighbour);
  int ci = (nc == coord) ? 0 : cast(int)coords[1..5].countUntil(nc) + 1;
  if (ci == 0 && nc != coord) return true;  // not found in any cache
  if (ci < 0 || ci >= 5) return true;
  int[3] ln = wd.localCoord(neighbour);
  if (ln[1] < 0) return false;
  if (ln[1] >= wd.chunkHeight) return true;
  int ni = wd.tileIndex(ln);
  if (ni < 0 || ni >= cast(int)tileCache[ci].length) return true;
  return tileCache[ci][ni] == ResourceType.None;
}

/** Pre-compute noise per (x,z) column for a chunk and its 4 neighbours */
NoiseCache[5] buildNoiseCaches(immutable(WorldData) wd, const int[3][5] coords) {
  NoiseCache[5] caches;
  foreach(ci; 0..5) {
    for (int x = 0; x < wd.chunkSize; x++) {
      for (int z = 0; z < wd.chunkSize; z++) {
        auto wc = wd.worldCoord(coords[ci], [x, 0, z]);
        caches[ci][x + z * wd.chunkSize] = noise2D(wc[0], wc[2], wd.seed[0]);
      }
    }
  }
  return caches;
}

/** Build tile type array for one chunk direction from its noise cache */
ResourceType[] buildTileTypes(immutable(WorldData) wd, int[3] coord, const NoiseCache nc, bool needMaterial) {
  ResourceType[] types;
  types.length = wd.tileCount;
  for (int z = 0; z < wd.chunkSize; z++) {
    for (int x = 0; x < wd.chunkSize; x++) {
      float h0 = nc[x + z * wd.chunkSize];
      int s = cast(int)(h0 * sqrt(h0) * (wd.chunkHeight - 1));
      ResourceType surfaceType = ResourceType.Stone01;  // placeholder for neighbours
      if (needMaterial) {
        auto wc = wd.worldCoord(coord, [x, 0, z]);
        surfaceType = heightToResource(h0, noise2D(wc[0], wc[2], wd.seed[1]));
      }
      int base = z * wd.chunkHeight * wd.chunkSize + x;
      for (int y = 0; y < wd.chunkHeight; y++) {
        types[base + y * wd.chunkSize] = y > s ? ResourceType.None : y == 0 ? ResourceType.Lava : y < s ? ResourceType.Stone01 : surfaceType;
      }
    }
  }
  if(auto cm = coord in wd.diffs) foreach(idx, type; *cm) types[idx] = type;
  return types;
}

/** helper that builds just one face */
@nogc float[12] faceData(int f, float px, float py, float pz, float ts, float th) nothrow {
  final switch(f) {
    case 0: return [  0,  0,  ts,   1,  0,  0,   0,  th,  0,   px+ts/2, py,      pz      ];
    case 1: return [  0,  0, -ts,  -1,  0,  0,   0,  th,  0,   px-ts/2, py,      pz      ];
    case 2: return [ ts,  0,   0,   0,  1,  0,   0,   0, ts,   px,      py+th/2, pz      ];
    case 3: return [ ts,  0,   0,   0, -1,  0,   0,   0,-ts,   px,      py-th/2, pz      ];
    case 4: return [-ts,  0,   0,   0,  0,  1,   0,  th,  0,   px,      py,      pz+ts/2 ];
    case 5: return [ ts,  0,   0,   0,  0, -1,   0,  th,  0,   px,      py,      pz-ts/2 ];
  }
}

/** Record a tile's AABB into chunk bounds and per-tile pick data (if it produced faces) */
void addTileBounds(ref ChunkData data, float[3] lo, float[3] hi, int i, size_t faceStart) {
  expandBounds(data.bmin, data.bmax, lo);
  expandBounds(data.bmin, data.bmax, hi);
  if (data.tileInstances.length > faceStart) {
    data.tileBmin ~= lo;
    data.tileBmax ~= hi;
    data.pickIndices ~= i;
  }
}

/** Generate tile face instances, AABB, and pick data with neighbour culling */
void buildTileGeometry(immutable(WorldData) wd, int[3] coord, const ResourceType[][5] tileCache, const int[3][5] coords, ref ChunkData data) {
  float ts = wd.tileSize, th = wd.tileHeight;
  int dz = wd.chunkHeight * wd.chunkSize, dy = wd.chunkSize;
  data.tileInstances.reserve(wd.tileCount);
  data.tileIndices.reserve(wd.tileCount);
  data.tileBmin.reserve(wd.chunkSize * wd.chunkSize);
  data.tileBmax.reserve(wd.chunkSize * wd.chunkSize);
  data.pickIndices.reserve(wd.chunkSize * wd.chunkSize);
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tileTypes[i] == ResourceType.None) continue;
    auto lc = wd.tileCoord(i);
    bool onBoundary = wd.onChunkBoundary(lc);
    if (!onBoundary && wd.isBuried(data.tileTypes, i, lc)) continue;
    auto wc = wd.worldCoord(coord, lc);
    float[3] p = wd.worldPos(wc);
    float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
    auto neighbours = wd.tileNeighbours(wc);
    size_t faceStart = data.tileInstances.length;
    foreach (f; 0 .. 6) {
      bool exposed;
      if (!onBoundary) {
        auto ln = wd.localCoord(neighbours[f]);
        exposed = ln[1] < 0 ? false : ln[1] >= wd.chunkHeight ? true : tileCache[0][wd.tileIndex(ln)] == ResourceType.None;
      } else { exposed = wd.isFaceExposed(tileCache, coords, neighbours[f], coord); }
      if (!exposed) continue;
      data.tileInstances ~= DrawInstance(cast(uint)data.tileTypes[i], faceData(f, px, py, pz, ts, th));
      data.tileIndices ~= i;
    }
    data.addTileBounds([px - ts/2, py - th/2, pz - ts/2], [px + ts/2, py + th/2, pz + ts/2], i, faceStart);
  }
}

/** Build chunk geometry data in a worker thread: generates tile instances with neighbour culling */
ChunkData buildChunkData(immutable(WorldData) wd, int[3] coord) {
  int[3][5] coords = [coord, [coord[0]+1, 0, coord[2]], [coord[0]-1, 0, coord[2]], [coord[0], 0, coord[2]+1], [coord[0], 0, coord[2]-1]];
  auto noiseCaches = wd.buildNoiseCaches(coords);
  ResourceType[][5] tileCache;
  foreach(ci; 0..5) tileCache[ci] = wd.buildTileTypes(coords[ci], noiseCaches[ci], ci == 0);
  ChunkData data = ChunkData(coord, tileCache[0]);
  wd.buildTileGeometry(coord, tileCache, coords, data);
  foreach(ref ft; features) { data.featureData[ft.name] = buildFeatureData(wd, coord, data.tileTypes, ft); }
  return data;
}

/** Find the best intersecting tile in the world given a ray, returns world coord or [int.min,0,0] */
bool getBestTile(ref GameApp app, float[3][2] ray, out int[3] wc) { return(app.getBestTile(ray, app.getHits(ray, false), wc)); }

bool getBestTile(ref GameApp app, float[3][2] ray, Intersection[] hits, out int[3] wc) {
  Intersection best;
  foreach(ref hit; hits) {
    auto chunk = cast(Chunk)app.objects[hit.idx[0]];
    if(chunk is null) continue;
    for(size_t j = 0; j < chunk.tileBmin.length; j++) {
      auto i = ray.intersects(chunk.tileBmin[j], chunk.tileBmax[j], hit.idx[0], j);
      if(i.intersects && (!best.intersects || i.tmin < best.tmin)) best = i;
    }
  }
  if(!best.intersects) return false;
  auto chunk = cast(Chunk)app.objects[best.idx[0]];
  auto local = app.world.tileCoord(chunk.pickIndices[best.idx[1]]);
  wc = app.world.worldCoord(chunk.coord, local);
  return true;
}

/** Finalize a chunk on the main thread: set up GPU resources, compute chunk AABB, add to scene */
void finalizeChunk(ref GameApp app, ChunkData data) {
  if (data.coord !in app.world.pendingChunks) return;
  if (data.tileInstances.length == 0) { app.world.pendingChunks.remove(data.coord); return; }

  Chunk chunk = new Chunk(data, app.world);
  chunk.tiles.box = new BoundingBox();
  chunk.tiles.box.setDimensions(data.bmin, data.bmax);

  if (data.coord in app.world.chunks) {
    auto oldTiles = app.world.chunks[data.coord].tiles;
    oldTiles.instances = chunk.tiles.instances.dup;
    oldTiles.instances.buffered = false;
    chunk.tiles = oldTiles;
    app.world.chunks[data.coord].deAllocate = true;
  } else { app.objects ~= chunk.tiles; }
  app.objects ~= chunk;

  app.world.chunks[data.coord] = chunk;
  app.world.chunks[data.coord].dirty = false;
  app.world.pendingChunks.remove(data.coord);
  app.world.pendingBuildTiles = app.world.pendingBuildTiles.filter!(t => app.world.chunkCoord(t) != data.coord).array;
  app.world.pendingMineTiles = app.world.pendingMineTiles.filter!(t => app.world.chunkCoord(t) != data.coord).array;

  // Add trees to the chunk
  foreach(ref ft; features) {
    if(ft.name !in app.world.features) app.world.features[ft.name] = null;
    if(ft.name !in app.world.pendingFeatures) app.world.pendingFeatures[ft.name] = null;
    if(data.coord !in app.world.features[ft.name] && data.coord !in app.world.pendingFeatures[ft.name]){
      app.world.pendingFeatures[ft.name][data.coord] = data.featureData[ft.name];
    }
  }

  if(app.verbose) SDL_Log("finalizeChunk: processing %d pending unsettle tiles", cast(int)app.world.pendingUnsettle.length);
  foreach(tile; app.world.pendingUnsettle) app.world.unsettleBlocks(app.world.blocks, tile);
  app.world.pendingUnsettle = [];
  app.camera.isDirty = true;
}
