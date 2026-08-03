/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import animal : seedChunkAnimals;
import block : unsettleBlocks;
import clouds : requestCloudRebuild, seedClouds;
import deletion : deAllocate;
import game : GameApp;
import gameobjects : Chunk;
import lattice : surfaceLevel, tileCoord, tileIndex, tileToWorld, worldToTile, onChunkBoundary, chunkCoord, localCoord, worldCoord, tileNeighbours;
import intersection : intersects;
import tile : getTile, isBuried, isSolid;
import hits : getHits;
import noise : noise2D;
import textures : idx;
import feature : buildFeatureData;
import vector : cross, dot;

/** Holds raw tile data and instanced rendering data for a chunk */
struct ChunkData {
  int[3] coord;                                             /// Chunk coordinate in chunk-space
  ResourceType[] tileTypes;                                 /// Tile type for each tile in the chunk
  ubyte[] waterLevel;                                       /// 0 = none, 1..6 = depth; parallel to tileTypes
  SparseSet wetCells;                                       /// indices where waterLevel > 0
  SparseSet active;                                         /// parallel to waterLevel; true = needs simulating. Always implies waterLevel[i] > 0.
  SparseSet touched;                                        /// local indices written this sim tick (dense, hash-free; cleared each tick)
  ubyte[] waterNext;                                        /// per-tick pending level (parallel to waterLevel); valid only at `touched` indices
  bool waterDirty = false;                                  /// Water dirty ?
  float[3][] tileBmin;                                      /// Per-tile AABB minimum (narrow-phase picking)
  float[3][] tileBmax;                                      /// Per-tile AABB maximum (narrow-phase picking)
  int[] pickIndices;                                        /// Maps pick result index back to tile index in tileTypes
  DrawInstance[] tileInstances;                             /// GPU instances for all visible tile faces
  Feature[][string] featureData;                            /// Chunk Features
}

struct ChunkField {
  LatticeMap!Chunk loaded;
  LatticeMap!bool pending;
  int[3][] unsettle, build, mine;
  alias loaded this;
}

/** Build the full tile-type array for a chunk column-by-column from height/material noise */
ResourceType[] buildTileTypes(immutable(WorldData) wd, int[3] coord) {
  ResourceType[] types;
  types.length = wd.tileCount;
  for (int z = 0; z < wd.chunkSize; z++) {
    for (int x = 0; x < wd.chunkSize; x++) {
      auto wc = wd.worldCoord(coord, [x, 0, z]);
      float h0 = noise2D(wc[0], wc[2], wd.seed[0]);
      int s = surfaceLevel(h0, wd.chunkHeight);
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

/** True if face `f` of the tile at world-coord `wc` is exposed (neighbour empty / above chunk). */
@nogc bool faceExposed(immutable(WorldData) wd, ref ChunkData data, int[3] coord, int[3] wc, int f) nothrow {
  auto n = tileNeighbours(wc)[f];
  if (wd.chunkCoord(n) == coord) {
    auto ln = wd.localCoord(n);
    return ln[1] < 0 ? false : ln[1] >= wd.chunkHeight ? true : data.tileTypes[wd.tileIndex(ln)] == ResourceType.None;
  }
  return !wd.isSolid(n);
}

/** One instance covering a w×d tile run of face `f` at plane-tile (x0,y,z0); UV tiles w×d. */
@nogc DrawInstance mergedFace(immutable(WorldData) wd, int[3] coord, int f, int x0, int y, int z0, int w, int d, ResourceType mat) nothrow {
  float ts = wd.tileSize, th = wd.tileHeight;
  float[3] a = wd.worldPos(wd.worldCoord(coord, [x0,       y, z0]));
  float[3] b = wd.worldPos(wd.worldCoord(coord, [x0 + w-1, y, z0 + d-1]));
  float px = (a[0] + b[0]) * 0.5f;
  float py =  a[1] + wd.yOffset;
  float pz = (a[2] + b[2]) * 0.5f;
  float[12] fd = faceData(f, px, py, pz, ts, th);
  fd[0] *= w; fd[1] *= w; fd[2] *= w;
  fd[6] *= d; fd[7] *= d; fd[8] *= d;
  auto inst = DrawInstance(fd, cast(int)mat, f);
  inst.uvRect = [0.0f, 0.0f, cast(float)w, cast(float)d];
  return inst;
}

/** Per-tile pick AABBs for every surface tile — render-independent, keeps picking at tile granularity. */
void buildTileBounds(immutable(WorldData) wd, int[3] coord, ref ChunkData data) {
  float ts = wd.tileSize, th = wd.tileHeight;
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tileTypes[i] == ResourceType.None) continue;
    auto lc = wd.tileCoord(i);
    if (!wd.onChunkBoundary(lc) && wd.isBuried(data.tileTypes, i, lc)) continue;
    auto wc = wd.worldCoord(coord, lc);
    bool exposed = false;
    foreach (f; 0 .. 6) if (wd.faceExposed(data, coord, wc, f)) { exposed = true; break; }
    if (!exposed) continue;
    float[3] p = wd.worldPos(wc); float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
    data.tileBmin ~= [px - ts/2, py - th/2, pz - ts/2];
    data.tileBmax ~= [px + ts/2, py + th/2, pz + ts/2];
    data.pickIndices ~= i;
  }
}

/** Greedy-merge exposed horizontal faces (f = 2 top, 3 bottom) into spanned quads, per y-plane. */
void mergeHorizontalFaces(immutable(WorldData) wd, int[3] coord, ref ChunkData data, int f) {
  immutable cs = wd.chunkSize;
  auto cell = new ResourceType[cs * cs];   // material with an exposed face at (x,z), else None
  auto used = new bool[cs * cs];
  for (int y = 0; y < wd.chunkHeight; y++) {
    cell[] = ResourceType.None; used[] = false;
    bool any = false;
    for (int z = 0; z < cs; z++) for (int x = 0; x < cs; x++) {
      auto t = data.tileTypes[wd.tileIndex([x, y, z])];
      if (t == ResourceType.None) continue;
      if (wd.faceExposed(data, coord, wd.worldCoord(coord, [x, y, z]), f)) { cell[z*cs + x] = t; any = true; }
    }
    if (!any) continue;
    for (int z = 0; z < cs; z++) for (int x = 0; x < cs; x++) {
      int k = z*cs + x;
      if (used[k] || cell[k] == ResourceType.None) continue;
      auto mat = cell[k];
      int w = 1; while (x + w < cs && !used[k + w] && cell[k + w] == mat) w++;
      int d = 1;
      grow: while (z + d < cs) {
        for (int xx = 0; xx < w; xx++) { int kk = (z + d)*cs + x + xx; if (used[kk] || cell[kk] != mat) break grow; }
        d++;
      }
      for (int dz = 0; dz < d; dz++) for (int dx = 0; dx < w; dx++) used[(z + dz)*cs + x + dx] = true;
      data.tileInstances ~= wd.mergedFace(coord, f, x, y, z, w, d, mat);
    }
  }
}

/** Emit side faces (f = 0,1,4,5) one instance per face (unmerged for now). */
void emitVerticalFaces(immutable(WorldData) wd, int[3] coord, ref ChunkData data) {
  float ts = wd.tileSize, th = wd.tileHeight;
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tileTypes[i] == ResourceType.None) continue;
    auto lc = wd.tileCoord(i);
    if (!wd.onChunkBoundary(lc) && wd.isBuried(data.tileTypes, i, lc)) continue;
    auto wc = wd.worldCoord(coord, lc);
    float[3] p = wd.worldPos(wc); float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
    foreach (f; [0, 1, 4, 5]) {
      if (!wd.faceExposed(data, coord, wc, f)) continue;
      data.tileInstances ~= DrawInstance(faceData(f, px, py, pz, ts, th), cast(int)data.tileTypes[i], f);
    }
  }
}

/** Generate tile geometry: per-tile pick AABBs, greedy-merged horizontal faces, unmerged sides. */
void buildTileGeometry(immutable(WorldData) wd, int[3] coord, ref ChunkData data) {
  wd.buildTileBounds(coord, data);            // pick AABBs (per-tile, unchanged granularity)
  wd.mergeHorizontalFaces(coord, data, 2);    // tops
  wd.mergeHorizontalFaces(coord, data, 3);    // bottoms
  wd.emitVerticalFaces(coord, data);          // sides (merge later if needed)
}

/** Build chunk geometry data in a worker thread: generates tile instances with neighbour culling */
ChunkData buildChunkData(immutable(WorldData) wd, int[3] coord) {
  ChunkData data = ChunkData(coord, wd.buildTileTypes(coord));
  data.waterLevel.length = data.tileTypes.length;   // all zero = no water
  data.wetCells.init(data.tileTypes.length);
  data.active.init(data.tileTypes.length);
  data.waterNext.length = data.tileTypes.length;
  data.touched.init(data.tileTypes.length);
  if(auto wm = coord in wd.waterDiffs){
    foreach(idx, lvl; *wm) {
      data.waterLevel[cast(int)idx] = lvl;
      data.wetCells ~= cast(int)idx;
      data.active ~= cast(int)idx;
    }
  }
  wd.buildTileGeometry(coord, data);
  foreach(ref ft; features) { data.featureData[ft.name] = buildFeatureData(wd, coord, data.tileTypes, ft); }
  return data;
}

/** Find the best intersecting tile in the world given a ray, returns world coord or [int.min,0,0] */
bool getBestTile(ref GameApp app, float[3][2] ray, out int[3] wc) { return(app.getBestTile(ray, app.getHits(ray, false), wc)); }

bool getBestTile(const GameApp app, float[3][2] ray, Intersection[] hits, out int[3] wc) {
  Intersection best;
  foreach(ref hit; hits) {
    auto chunk = cast(const(Chunk))app.objects[hit.idx[0]];
    if(chunk is null) continue;
    for(size_t j = 0; j < chunk.tileBmin.length; j++) {
      auto i = ray.intersects(chunk.tileBmin[j], chunk.tileBmax[j], hit.idx[0], j);
      if(i.intersects && (!best.intersects || i.tmin < best.tmin)) best = i;
    }
  }
  if(!best.intersects) return false;
  auto chunk = cast(const(Chunk))app.objects[best.idx[0]];
  auto local = app.world.tileCoord(chunk.pickIndices[best.idx[1]]);
  wc = app.world.worldCoord(chunk.coord, local);
  return true;
}

/** Finalize a chunk on the main thread: set up GPU resources, compute chunk AABB, add to scene */
void finalizeChunk(ref GameApp app, ChunkData data) {
  if (data.coord !in app.world.chunks.pending) return;
  if (data.tileInstances.length == 0) { app.world.chunks.pending.remove(data.coord); return; }

  Chunk chunk = new Chunk(data, app.world);

  if (data.coord in app.world.chunks) {
    auto oldTiles = app.world.chunks[data.coord].tiles;
    oldTiles.instances = chunk.tiles.instances.dup;
    oldTiles.syncInstances();
    chunk.tiles = oldTiles;
    chunk.waterLevel = app.world.chunks[data.coord].waterLevel;   // preserve water across rebuild
    chunk.wetCells = app.world.chunks[data.coord].wetCells;       // preserve wet cells
    chunk.active = app.world.chunks[data.coord].active;           // preserve active mask
    app.world.chunks[data.coord].deAllocate = true;
    foreach(ref slot; app.shadows.slots) { slot.pending = true; }
  } else {
    chunk.tiles.box = new BoundingBox();
    app.objects ~= chunk.tiles;
    app.seedChunkAnimals(data);          // first generation of this chunk: spawn its noise animals
  }
  app.objects ~= chunk;

  app.world.chunks[data.coord] = chunk;
  app.world.seedClouds(data.coord);
  app.requestCloudRebuild();
  app.world.chunks[data.coord].dirty = false;
  app.world.chunks.pending.remove(data.coord);
  app.world.chunks.build = app.world.chunks.build.filter!(t => app.world.chunkCoord(t) != data.coord).array;
  app.world.chunks.mine = app.world.chunks.mine.filter!(t => app.world.chunkCoord(t) != data.coord).array;

  // Add trees to the chunk
  foreach(ref ft; features) {
    if(ft.name !in app.world.vegetation) app.world.vegetation[ft.name] = null;
    if(ft.name !in app.world.vegetation.pending) app.world.vegetation.pending[ft.name] = null;
    if(data.coord !in app.world.vegetation[ft.name] && data.coord !in app.world.vegetation.pending[ft.name] && data.coord !in app.world.vegetation.modified) {
      app.world.vegetation.pending[ft.name][data.coord] = data.featureData[ft.name];
    }
  }

  if(app.verbose) SDL_Log("finalizeChunk: processing %d pending unsettle tiles", cast(int)app.world.chunks.unsettle.length);
  foreach(tile; app.world.chunks.unsettle) { app.world.unsettleBlocks(app.world.drops, tile); }
  app.world.chunks.unsettle = [];
}
