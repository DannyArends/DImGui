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
import lattice : surfaceLevel, tileCoord, tileIndex, onChunkBoundary, chunkCoord, worldCoord;
import intersection : intersects;
import tile : isBuried, isSolid;
import noise : noise2D;
import textures : idx;
import feature : buildFeatureData;

enum float SEAM_BLEED = 0.001f;   // fraction of a tile; closes T-junction hairlines

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

/** Per-face plane geometry: axis mapping, plane extents, and tileTypes-index strides. */
struct FacePlane {
  int da, ua, va;        /// normal / U / V axis indices
  int dMax, uMax, vMax;  /// tile extent along depth / U / V
  int sd, su, sv;        /// linear index step per depth / column / row
}

/** Derive the plane descriptor for face direction `f`. */
@nogc FacePlane facePlane(immutable(WorldData) wd, int f) nothrow {
  immutable int[3] ext = [wd.chunkSize, wd.chunkHeight, wd.chunkSize];
  immutable int[3] st = [1, wd.chunkSize, wd.chunkHeight * wd.chunkSize];
  immutable int da = FACE_AXES[f][0], ua = FACE_AXES[f][1], va = FACE_AXES[f][2];
  return FacePlane(da, ua, va, ext[da], ext[ua], ext[va], st[da], st[ua], st[va]);
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
  if(auto cm = coord in wd.diffs) { foreach(idx, type; *cm) { types[idx] = type; } }
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

/** True if face 'f' of the tile at world-coord 'wc' is exposed (neighbour empty / above chunk). */
@nogc bool faceExposed(immutable(WorldData) wd, ref ChunkData data, int[3] coord, int[3] lc, int f) nothrow {
  immutable int cs = wd.chunkSize, ch = wd.chunkHeight;
  int[3] ln = [lc[0] + FACE_OFFSETS[f][0], lc[1] + FACE_OFFSETS[f][1], lc[2] + FACE_OFFSETS[f][2]];
  if (ln[0] >= 0 && ln[0] < cs && ln[2] >= 0 && ln[2] < cs) {      // neighbour in this chunk - no division
    return ln[1] < 0 ? false : ln[1] >= ch ? true : data.tileTypes[wd.tileIndex(ln)] == ResourceType.None;
  }
  return !wd.isSolid(wd.worldCoord(coord, ln));                    // chunk border only: cross into neighbour
}

/** Per-face [normalAxis, uAxis, vAxis] as tile-space indices (0=X, 1=Y, 2=Z). */
static immutable int[3][6] FACE_AXES = [
  [0, 2, 1], [0, 2, 1],   // f0/f1 (±X): plane U=Z, V=Y
  [1, 0, 2], [1, 0, 2],   // f2/f3 (±Y): plane U=X, V=Z
  [2, 0, 1], [2, 0, 1],   // f4/f5 (±Z): plane U=X, V=Y
];

/** One instance covering a w×d tile run of face 'f' at plane-tile (x0,y,z0); UV tiles w x d. */
@nogc DrawInstance mergedFace(immutable(WorldData) wd, int[3] coord, int f, int[3] o, int u, int v, ResourceType mat) nothrow {
  float ts = wd.tileSize, th = wd.tileHeight;
  int ua = FACE_AXES[f][1], va = FACE_AXES[f][2];
  int[3] c = o; c[ua] += (u - 1); c[va] += (v - 1);          // far corner along the face's U/V axes
  float[3] a = wd.worldPos(wd.worldCoord(coord, o));
  float[3] b = wd.worldPos(wd.worldCoord(coord, c));
  float px = (a[0] + b[0]) * 0.5f;
  float py = (a[1] + b[1]) * 0.5f + wd.yOffset;              // midpoint: correct for Y-spanning walls
  float pz = (a[2] + b[2]) * 0.5f;
  float[12] fd = faceData(f, px, py, pz, ts, th);
  float su = u + SEAM_BLEED, sv = v + SEAM_BLEED;
  fd[0] *= su; fd[1] *= su; fd[2] *= su;
  fd[6] *= sv; fd[7] *= sv; fd[8] *= sv;
  auto inst = DrawInstance(fd, cast(int)mat, f);
  inst.uvRect = [0.0f, 0.0f, cast(float)u, cast(float)v];
  return inst;
}

/** Per-tile pick AABBs for every surface tile — render-independent, keeps picking at tile granularity. */
void buildTileBounds(immutable(WorldData) wd, int[3] coord, ref ChunkData data) {
  float ts = wd.tileSize, th = wd.tileHeight;
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tileTypes[i] == ResourceType.None) continue;
    auto lc = wd.tileCoord(i);
    if (!wd.onChunkBoundary(lc) && wd.isBuried(data.tileTypes, i, lc)) continue;
    bool exposed = false;
    foreach (f; 0 .. 6) if (wd.faceExposed(data, coord, lc, f)) { exposed = true; break; }
    if (!exposed) continue;
    float[3] p = wd.worldPos(wd.worldCoord(coord, lc)); float px = p[0], py = p[1] + wd.yOffset, pz = p[2];
    data.tileBmin ~= [px - ts/2, py - th/2, pz - ts/2];
    data.tileBmax ~= [px + ts/2, py + th/2, pz + ts/2];
    data.pickIndices ~= i;
  }
}

/** Fill the plane grid at depth `dpt` with exposed-face materials; true if any face was exposed. */
bool fillPlane(immutable(WorldData) wd, int[3] coord, ref ChunkData data, int f, FacePlane p, int dpt, ResourceType[] cell, bool[] used) {
  cell[0 .. p.uMax * p.vMax] = ResourceType.None;
  used[0 .. p.uMax * p.vMax] = false;
  bool any = false;
  for (int vv = 0; vv < p.vMax; vv++) {
    immutable int row = vv * p.uMax;                               // plane-grid row base
    int idx = dpt * p.sd + vv * p.sv;                              // tileTypes index, stepped by su per column
    for (int uu = 0; uu < p.uMax; uu++, idx += p.su) {
      auto t = data.tileTypes[idx];
      if (t == ResourceType.None) continue;
      int[3] lc; lc[p.da] = dpt; lc[p.ua] = uu; lc[p.va] = vv;
      if (wd.faceExposed(data, coord, lc, f)) { cell[row + uu] = t; any = true; }
    }
  }
  return any;
}

/** Greedy-merge the filled plane grid into instances: one quad per maximal same-material rectangle. */
void mergePlane(immutable(WorldData) wd, int[3] coord, ref ChunkData data, int f, FacePlane p, int dpt, ResourceType[] cell, bool[] used) {
  for (int vv = 0; vv < p.vMax; vv++) for (int uu = 0; uu < p.uMax; uu++) {
    int k = vv*p.uMax + uu;
    if (used[k] || cell[k] == ResourceType.None) continue;
    auto mat = cell[k];
    int w = 1; while (uu + w < p.uMax && !used[k + w] && cell[k + w] == mat) w++;   // extend width along u

    /** True if the whole w-wide strip at row r is unused and all material 'mat'. */
    bool strip(int r) {
      foreach (x; 0 .. w) { immutable kk = r*p.uMax + uu + x; if (used[kk] || cell[kk] != mat) return false; }
      return true;
    }
    int h = 1; while (vv + h < p.vMax && strip(vv + h)) h++;                         // extend height along v
    for (int dv = 0; dv < h; dv++) for (int du = 0; du < w; du++) used[(vv + dv)*p.uMax + uu + du] = true;
    int[3] o; o[p.da] = dpt; o[p.ua] = uu; o[p.va] = vv;
    data.tileInstances ~= wd.mergedFace(coord, f, o, w, h, mat);
  }
}

/** Generate tile geometry: per-tile pick AABBs, greedy-merged faces. */
void buildTileGeometry(immutable(WorldData) wd, int[3] coord, ref ChunkData data) {
  immutable int surf = wd.chunkSize * wd.chunkSize;               // surface-area estimate for reservation
  data.tileInstances.reserve(surf * 2);
  data.tileBmin.reserve(surf); data.tileBmax.reserve(surf); data.pickIndices.reserve(surf);
  wd.buildTileBounds(coord, data);              // pick AABBs (per-tile, unchanged granularity)
  immutable int plane = wd.chunkSize * (wd.chunkSize > wd.chunkHeight ? wd.chunkSize : wd.chunkHeight);
  auto cell = new ResourceType[plane];          // scratch reused across all six sweeps
  auto used = new bool[plane];
  foreach (f; 0 .. 6) {
    immutable p = wd.facePlane(f);
    for (int dpt = 0; dpt < p.dMax; dpt++) {
      if (wd.fillPlane(coord, data, f, p, dpt, cell, used)){ wd.mergePlane(coord, data, f, p, dpt, cell, used); }
    }
  }
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
