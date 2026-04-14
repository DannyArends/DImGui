/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import geometry : texture, deAllocate, position;
import io : readFile, fsize;
import intersection : intersects;
import textures : mapTextures;
import tileatlas : tileData, tileUVTransform;
import matrix : translate, scale, multiply;
import vector : expandBounds;
import world : placeTile, setTile;
import events : getHits;
import camera : castRay;

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
  this() { super(); isSelectable = false; name = (){ return "Tiles"; }; }
}

/** Spatial container for a chunk, selectable via its AABB, delegates rendering to Block
 */
class Chunk : Cube {
  ChunkData data;
  Geometry tiles;
  bool dirty = false;
  alias data this;

  this(ChunkData cd) {
    super();
    data = cd;
    indices = [];
    instances = [Instance()];
    tiles = new Tiles();
    tiles.instances = cd.tileInstances;
    name = (){ return "Chunk"; };
  }
}

/** Check if a face is exposed / uncovered
 * TODO: should use TileType[][int[3]] (coordinate as index) but that doesn't work on Android
 */
bool isFaceExposed(immutable(WorldData) wd, const TileType[][5] tileCache, const int[3][5] coords, int[3] neighbour, int[3] coord) {
  int[3] nc = wd.chunkCoord(neighbour);
  if (nc == coord) { /// Same chunk
    int[3] ln = wd.localCoord(neighbour);
    if (ln[1] < 0) return false;
    if (ln[1] >= wd.chunkHeight) return true;
    int ni = wd.tileIndex(ln);
    if (ni < 0 || ni >= cast(int)tileCache[0].length) return true;
    return tileCache[0][ni] == TileType.None;
  }
  foreach (ci; 1 .. 5) { /// Check all neighbouring chunks
    if (coords[ci] != nc) continue;
    int[3] ln = wd.localCoord(neighbour);
    if (ln[1] < 0) return false;
    if (ln[1] >= wd.chunkHeight) return true;
    int ni = wd.tileIndex(ln);
    if (ni < 0 || ni >= cast(int)tileCache[ci].length) return true;
    return tileCache[ci][ni] == TileType.None;
  }
  return true;
}

/** Load the TileCache, 
 * TODO: should use TileType[][int[3]] (coordinate as index) but that doesn't work on Android
 */
TileType[][5] loadTileCache(immutable(WorldData) wd, int[3][5] coords, int[3] coord) {
  TileType[][5] tileCache;
  foreach (ci; 0 .. 5) {
    auto path = wd.chunkPath(coords[ci]);
    if (fsize(path, false) == wd.tileCount * TileType.sizeof) {
      tileCache[ci] = cast(TileType[])readFile(path);
    } else {
      SDL_RemovePath(path);
      tileCache[ci] = (cast(TileType*)malloc(wd.tileCount * TileType.sizeof))[0 .. wd.tileCount];
      for (int i = 0; i < wd.tileCount; i++) tileCache[ci][i] = wd.getTile(wd.worldCoord(coords[ci], wd.tileCoord(i)));
    }
  }
  return tileCache;
}

int[3] getGhostTile(ref App app, float[3][2] ray) {
  Intersection best;
  foreach (ref hit; app.getHits(ray, false)) {
    auto chunk = cast(Chunk)app.objects[hit.idx[0]];
    if (chunk is null) continue;
    for (size_t j = 0; j < chunk.tileBmin.length; j++) {
      auto i = ray.intersects(chunk.tileBmin[j], chunk.tileBmax[j], hit.idx[0], j);
      if (i.intersects && (!best.intersects || i.tmin < best.tmin)) best = i;
    }
  }
  if (!best.intersects) return [int.min, 0, 0];
  auto chunk = cast(Chunk)app.objects[best.idx[0]];
  auto local = app.world.tileCoord(chunk.pickIndices[best.idx[1]]);
  auto wc = app.world.worldCoord(chunk.coord, local);
  // Find which neighbour face was hit using ray direction
  float[3] dir = ray[1];
  int[3][6] neighbours = app.world.tileNeighbours(wc);
  float[3][6] normals = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
  float bestDot = float.max;
  int bestFace = 0;
  foreach(f; 0..6) {
    float dot = dir[0]*normals[f][0] + dir[1]*normals[f][1] + dir[2]*normals[f][2];
    if(dot < bestDot) { bestDot = dot; bestFace = f; }
  }
  auto target = neighbours[bestFace];
  auto coord = app.world.chunkCoord(target);
  if(coord in app.world.chunks) {
    auto idx = app.world.tileIndex(app.world.localCoord(target));
    if(app.world.chunks[coord].tileTypes[idx] == TileType.None) return target;
  } else {
    if(app.world.getTile(target) == TileType.None) return target;
  }
  return [int.min, 0, 0];
}

void updateGhostTile(ref App app) {
  if(app.gui.selectedTile != TileType.None) {
    auto ray = app.camera.castRay(app.gui.io.MousePos.x, app.gui.io.MousePos.y);
    auto ghost = app.getGhostTile(ray);
    app.gui.ghostTile = ghost;
    if(ghost[0] != int.min) {
      auto wp = app.world.worldPos(ghost);
      app.gui.ghostCube.position([wp[0], wp[1] + app.world.yOffset, wp[2]]);
      auto name = tileData[app.gui.selectedTile].name;
      auto uvT = app.tileAtlas.tileUVTransform(name);
      foreach(ref inst; app.gui.ghostCube.instances) inst.uvT = uvT;
      app.gui.ghostCube.buffers[INSTANCE] = false;
      app.gui.ghostCube.isVisible = true;
    } else {
      app.gui.ghostCube.isVisible = false;
    }
  } else {
    app.gui.ghostTile = [int.min, 0, 0];
    app.gui.ghostCube.isVisible = false;
  }
}

/** Build chunk geometry data in a worker thread: generates tile instances with neighbour culling
 */
ChunkData buildChunkData(immutable(WorldData) wd, immutable(TileAtlas) ta, int[3] coord) {
  int[3][5] coords = [coord, [coord[0]+1, 0, coord[2]], [coord[0]-1, 0, coord[2]], [coord[0], 0, coord[2]+1], [coord[0], 0, coord[2]-1]];
  TileType[][5] tileCache = wd.loadTileCache(coords, coord);

  ChunkData data = ChunkData(coord, tileCache[0]);

  float ts = wd.tileSize, th = wd.tileHeight;
  for (int i = 0; i < wd.tileCount; i++) {
    if (data.tileTypes[i] == TileType.None) continue;
    auto wc = wd.worldCoord(coord, wd.tileCoord(i));
    auto uvT = ta.tileUVTransform(tileData[data.tileTypes[i]].name);
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

/** Two-phase world pick: broad phase via chunk BBs, narrow phase per block instance, updates highlight
 */
void pickWorld(ref App app, Intersection[] hits, float[3][2] ray) {
  Intersection best;
  foreach (ref hit; hits) {
    auto chunk = cast(Chunk)app.objects[hit.idx[0]];
    if (chunk is null) continue;
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
  if (data.tileInstances.length == 0) { app.world.pendingChunks.remove(data.coord); return; }

  Chunk chunk = new Chunk(data);
  float sx = app.world.chunkWorldSize;
  float sy = app.world.chunkHeight * app.world.tileHeight;
  float cx = data.coord[0] * sx + sx * 0.5f;
  float cz = data.coord[2] * sx + sx * 0.5f;
  float cy = sy * 0.5f + app.world.yOffset;
  chunk.instances[0].matrix = translate([cx, cy, cz]).multiply(scale([sx, sy, sx]));

  chunk.tiles.texture("3DTextures");
  chunk.tiles.box = new BoundingBox();
  chunk.tiles.box.setDimensions(data.bmin, data.bmax);
  chunk.tiles.box.instances = [Instance()]; // single instance, identity matrix

  // Replace old chunk objects in-place within app.objects to preserve mesh slot indices.
  // Appending new objects would shift meshdef for all subsequent objects, causing a one-frame
  // mismatch between the SSBO (updated immediately) and instance buffers (updated next frame).
  if (data.coord in app.world.chunks) {
    auto old = app.world.chunks[data.coord];
    foreach(ref o; app.objects) {
      if(o is old.tiles) { o = chunk.tiles; continue; }
      if(o is old) { o = chunk; continue; }
    }
    app.deAllocate(old.tiles);
    app.deAllocate(old);
  } else {
    app.objects ~= chunk.tiles;
    app.objects ~= chunk;
  }
  app.mapTextures(chunk.tiles);

  app.world.chunks[data.coord] = chunk;
  app.world.pendingChunks.remove(data.coord);
  app.camera.isDirty = true;
  app.shadows.dirty = true;
  app.buffers["MeshMatrices"].dirty[] = true;
}

