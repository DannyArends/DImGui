/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : unsettleBlocks;
import game : GameApp;
import gameobjects : Chunk;
import deletion : deAllocate;
import intersection : intersects;
import tile : getTile, tileIndex, tileCoord, tileToWorld, worldToTile, onChunkBoundary, isBuried, isSolid;
import hits : getHits;
import noise : noise2D;
import textures : idx;
import feature : buildFeatureData;
import vector : cross, dot;

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
}

/** Build the full tile-type array for a chunk column-by-column from height/material noise */
ResourceType[] buildTileTypes(immutable(WorldData) wd, int[3] coord) {
  ResourceType[] types;
  types.length = wd.tileCount;
  for (int z = 0; z < wd.chunkSize; z++) {
    for (int x = 0; x < wd.chunkSize; x++) {
      auto wc = wd.worldCoord(coord, [x, 0, z]);
      float h0 = noise2D(wc[0], wc[2], wd.seed[0]);
      int s = cast(int)(h0 * sqrt(h0) * (wd.chunkHeight - 1));
      ResourceType surfaceType = heightToResource(h0, noise2D(wc[0], wc[2], wd.seed[1]));
      int base = z * wd.chunkHeight * wd.chunkSize + x;
      for (int y = 0; y < wd.chunkHeight; y++) {
        types[base + y * wd.chunkSize] = y > s ? ResourceType.None : y == 0 ? ResourceType.Lava : y < s ? ResourceType.Stone01 : surfaceType;
      }
    }
  }
  if(auto cm = coord in wd.diffs) foreach(idx, type; *cm) types[idx] = type;
  return types;
}

/** Returns the 12-float instance data (offset/normal/extent/centre) for one cube face f */
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
  if (data.tileInstances.length > faceStart) {
    data.tileBmin ~= lo;
    data.tileBmax ~= hi;
    data.pickIndices ~= i;
  }
}

/** Generate tile face instances, AABB, and pick data with neighbour culling */
void buildTileGeometry(immutable(WorldData) wd, int[3] coord, ref ChunkData data) {
  float ts = wd.tileSize, th = wd.tileHeight;
  data.tileInstances.reserve(wd.tileCount);
  data.tileIndices.reserve(wd.tileCount);
  data.tileBmin.reserve(wd.chunkSize * wd.chunkSize);
  data.tileBmax.reserve(wd.chunkSize * wd.chunkSize);
  data.pickIndices.reserve(wd.chunkSize * wd.chunkSize);
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tileTypes[i] == ResourceType.None) continue;
    auto lc = wd.tileCoord(i);
    if (!wd.onChunkBoundary(lc) && wd.isBuried(data.tileTypes, i, lc)) continue;
    auto wc = wd.worldCoord(coord, lc);
    float[3] p = wd.worldPos(wc);
    float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
    auto neighbours = wd.tileNeighbours(wc);
    size_t faceStart = data.tileInstances.length;
    foreach (f; 0 .. 6) {
      bool exposed;
      if (wd.chunkCoord(neighbours[f]) == coord) {
        auto ln = wd.localCoord(neighbours[f]);
        exposed = ln[1] < 0 ? false : ln[1] >= wd.chunkHeight ? true : data.tileTypes[wd.tileIndex(ln)] == ResourceType.None;
      } else { exposed = !wd.isSolid(neighbours[f]); }
      if (!exposed) continue;
      data.tileInstances ~= DrawInstance(cast(uint)data.tileTypes[i], faceData(f, px, py, pz, ts, th));
      data.tileIndices ~= i;
    }
    data.addTileBounds([px - ts/2, py - th/2, pz - ts/2], [px + ts/2, py + th/2, pz + ts/2], i, faceStart);
  }
}

/** Build chunk geometry data in a worker thread: generates tile instances with neighbour culling */
ChunkData buildChunkData(immutable(WorldData) wd, int[3] coord) {
  ChunkData data = ChunkData(coord, wd.buildTileTypes(coord));
  wd.buildTileGeometry(coord, data);
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
    if(data.coord !in app.world.features[ft.name] && data.coord !in app.world.pendingFeatures[ft.name] && data.coord !in app.world.featuresModified) {
      app.world.pendingFeatures[ft.name][data.coord] = data.featureData[ft.name];
    }
  }

  if(app.verbose) SDL_Log("finalizeChunk: processing %d pending unsettle tiles", cast(int)app.world.pendingUnsettle.length);
  foreach(tile; app.world.pendingUnsettle){
    app.world.unsettleBlocks(app.world.blocks, tile);
    app.unsettleDwarves(tile);
  }
  app.world.pendingUnsettle = [];
}
