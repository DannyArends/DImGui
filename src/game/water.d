/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : faceData;
import clouds : CLOUD_STEP, cloudCell;
import lattice : tileBelow, tileCoord, tileIdx, tileToWorld, chunkCoord, worldCoord, flatten, unflatten, Diff;
import tile : neighbourAt, isStandable, standableNeighbour, getWater, setWater;
import vector : manhattan, manhattan2D;

enum ubyte WATER_MAX = 7;               // Maximum water density
enum int WATER_TARGET_ACTIVE = 1250;    // Desired number of live water cells in sim
enum float EVAP_DENSITY = 0.005f;       // Density added through water evaporation
enum uint EVAP_DEPLETE = 3000;          // Speed of evaporation

static immutable int[2][4] H = [[1,0],[-1,0],[0,1],[0,-1]];

/** An active cell queued for this tick's simulation: its chunk, local index, and world-coord. */
struct Active { Chunk chunk; int idx; int[3] wc; }

private struct Cell { Chunk chunk; int idx; }

/** Pending level of a resolved cell: next-buffer if written this tick, else committed dense level. */
private @nogc int pending(const Chunk chunk, int idx) nothrow {
  return chunk.touched.contains(idx) ? chunk.waterNext[idx] : chunk.waterLevel[idx];
}

/** Nearest reachable water: scans wet cells across loaded chunks, returns the standable
    tile to path to (in `standAt`) and the water cell to draw from (return value), or noTile. */
int[3] findNearestWater(const World world, const int[3] from, out int[3] standAt) {
  int[3] bestCell = noTile; standAt = noTile; float bestDist = float.max;
  foreach(coord, ch; world.chunks) {
    foreach(idx; ch.wetCells) {
      if(ch.waterLevel[idx] == 0) continue;
      int[3] wc = world.worldCoord(coord, world.tileCoord(idx));
      // stand on the water tile itself if standable, else an adjacent standable tile
      int[3] at = world.isStandable(wc) ? wc : world.standableNeighbour(wc);
      if(at == noTile) continue;
      float dist = manhattan(at, from);
      if(dist < bestDist) { bestDist = dist; bestCell = wc; standAt = at; }
    }
  }
  return bestCell;
}

/** Total live water-sim cells across all loaded chunks (sum of each chunk's active set). */
@nogc activeSim(const LatticeMap!Chunk chunks) {
  int active = 0;
  foreach(c; chunks){ active += cast(int)c.active.length; }
  return(active);
}

/** Apply a delta to a resolved cell's per-chunk next-buffer; marks it touched. No hashing. */
private void wrWater(Chunk chunk, int idx, int delta) {
  int cur = chunk.touched.contains(idx) ? chunk.waterNext[idx] : chunk.waterLevel[idx];
  chunk.waterNext[idx] = cast(ubyte)max(0, min(WATER_MAX, cur + delta));
  chunk.touched.add(idx);
}

/** One water simulation step. Spread then fall, crosses chunk boundaries. Iterates only wet cells. */
void waterTick(ref GameApp app) {
  Active[] act;

  // PHASE 1: GATHER
  foreach(coord, ch; app.world.chunks) {
    if(ch.active.length == 0) continue;
    foreach(idx; ch.active) act ~= Active(ch, idx, app.world.worldCoord(coord, app.world.tileCoord(idx)));
  }
  if(act.length == 0) return;

  bool[] moved; moved.length = act.length;

  // PHASE 2: SPREAD
  foreach(i, a; act) {
    int have = pending(a.chunk, a.idx);
    Cell[4] tgt;
    int n = app.world.spreadTargets(a.chunk, a.idx, have, tgt);
    if(n > 0) { Cell dst = tgt[uniform(0, n)]; wrWater(a.chunk, a.idx, -1); wrWater(dst.chunk, dst.idx, +1); moved[i] = true; }
  }

  // PHASE 3: FALL
  foreach(i, a; act) {
    Cell below;
    if(!app.world.canFall(a.chunk, a.idx, below)) continue;
    int mv = min(pending(a.chunk, a.idx), WATER_MAX - pending(below.chunk, below.idx));
    if(mv > 0) { wrWater(a.chunk, a.idx, -mv); wrWater(below.chunk, below.idx, +mv); moved[i] = true; }
  }

  // PHASE 4: COMMIT changed cells per touched chunk, then reset scratch
  foreach(coord, ch; app.world.chunks) {
    if(ch.touched.length == 0) continue;
    foreach(idx; ch.touched.keys) {
      if(ch.waterNext[idx] == ch.waterLevel[idx]) continue;
      app.world.setWater(app.world.worldCoord(coord, app.world.tileCoord(idx)), ch.waterNext[idx]);
    }
    ch.touched.clear();
  }

  // PHASE 5: DEACTIVATE unmoved-and-settled
  foreach(i, a; act) {
    if(moved[i]) continue;
    if(app.world.isSettled(a.chunk, a.idx)) a.chunk.active.remove(a.idx);
  }
}

/** Lower one cell's water without waking the sim */
void evaporateTick(ref GameApp app) {
  int active = app.world.chunks.activeSim();
  float ratio = active / cast(float)WATER_TARGET_ACTIVE;            // 1.0 at target
  int hi = cast(int)clamp(5.0f / (ratio + 0.05f), 2.0f, 50.0f);     // under target -> larger pulse, over -> smaller

  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    foreach(idx; chunk.wetCells.dup) {
      if(chunk.waterLevel[idx] == 0 || chunk.waterLevel[idx] >= (WATER_MAX-2)) continue;
      if(uniform(0, EVAP_DEPLETE) < (WATER_MAX - chunk.waterLevel[idx]) * 2) {
        int[3] wc = app.world.worldCoord(chunk.coord, app.world.tileCoord(idx));
        app.world.setWater(wc, cast(ubyte)(chunk.waterLevel[idx] - 1), false);
        auto cell = cloudCell(wc[0], wc[2]);
        auto dd = H[uniform(0, 4)];
        app.world.weather.density[[cell[0] + dd[0], cell[1] + dd[1]]] += uniform(1, hi) * EVAP_DENSITY;   // moisture rises and drifts to a neighbour
      }
    }
  }
}

/** Collect the lowest-level air neighbours water could spread into (4-connected, horizontal).
    Returns the count and fills `tgt` with up to 4 equally-low targets strictly below `have`;
    0 if the cell holds < 2 or no neighbour is lower. Reads pending levels from `next`. */
private int spreadTargets(ref World world, Chunk chunk, int idx, int have, out Cell[4] tgt) nothrow {
  if(have < 2) return 0;
  auto lc = world.tileCoord(idx);
  int bestLvl = have, n = 0;
  foreach(h; H) {
    int[3] nc; int nidx;
    if(!world.neighbourAt(chunk.coord, lc, [h[0], 0, h[1]], nc, nidx)) continue;
    Chunk nch = (nc == chunk.coord) ? chunk : world.chunks[nc];
    if(nch.tileTypes[nidx] != ResourceType.None) continue;
    int nl = pending(nch, nidx);
    if(nl < bestLvl) { bestLvl = nl; tgt[0] = Cell(nch, nidx); n = 1; }
    else if(nl == bestLvl && bestLvl < have){ tgt[n++] = Cell(nch, nidx); }
  }
  return n;
}

/** True if the cell below is air and not yet full, so water here can fall into it. */
private bool canFall(ref World world, Chunk chunk, int idx, out Cell below) nothrow {
  auto lc = world.tileCoord(idx);
  int[3] nc; int nidx;
  if(!world.neighbourAt(chunk.coord, lc, [0,-1,0], nc, nidx)) return false;
  Chunk nch = (nc == chunk.coord) ? chunk : world.chunks[nc];
  if(nch.tileTypes[nidx] != ResourceType.None) return false;
  if(pending(nch, nidx) >= WATER_MAX) return false;
  below = Cell(nch, nidx);
  return true;
}

/** True if the cell has water but can neither fall nor spread - i.e. nothing left to simulate this tick. */
private bool isSettled(ref World world, Chunk chunk, int idx) nothrow {
  int have = pending(chunk, idx);
  if(have <= 0) return true;
  Cell below;
  if(world.canFall(chunk, idx, below)) return false;
  Cell[4] tgt;
  if(world.spreadTargets(chunk, idx, have, tgt) > 0) return false;
  return true;
}

/** Rebuild the single world water object from all chunks' waterLevel. */
private DrawInstance[] rebuildChunkWaterInstances(const World world, const Chunk chunk) {
  DrawInstance[] inst;
  foreach(idx; chunk.wetCells) {
    ubyte lvl = chunk.waterLevel[idx];
    if(lvl == 0) continue;
    auto lc = world.tileCoord(idx);
    int[3] wc = world.data.worldCoord(chunk.coord, lc);
    float[3] p = world.data.tileToWorld(wc);
    float wh = world.tileHeight * (lvl / cast(float)WATER_MAX);
    float cy = p[1] - world.tileHeight * 0.5f + wh * 0.5f;
    foreach(f; 0 .. 6) {
      int[3] nc; int nidx; int nlvl = 0;
      if(world.neighbourAt(chunk.coord, lc, FACE_OFFSETS[f], nc, nidx)) {
        nlvl = ((nc == chunk.coord) ? chunk : world.chunks[nc]).waterLevel[nidx];
      }
      if(nlvl >= lvl) continue;
      inst ~= DrawInstance(faceData(f, p[0], cy, p[2], world.tileSize, wh), cast(int)ResourceType.Water);
    }
  }
  return(inst);
}

/** If any chunk's water changed, rebuild the single water object. */
void flushWaterDirty(ref GameApp app) {
  bool any = false;
  foreach(ref chunk; app.world.chunks) {
    if(!chunk.waterDirty) continue;
    if(!chunk.tiles.inFrustum) continue;  // skip off-screen: defer re-mesh until visible
    chunk.waterInstances = app.world.rebuildChunkWaterInstances(chunk);
    chunk.waterDirty = false;  // cleared only when actually re-meshed
    any = true;
  }
  if(!any || app.world.water is null) return;
  DrawInstance[] all;
  foreach(ref chunk; app.world.chunks){ all ~= chunk.waterInstances; }
  app.world.water.instances = all;
  app.world.water.syncInstances();
}

/** Snapshot all loaded chunks' water into waterDiffs, then flatten + save (mirrors saveDiffs). */
Diff!ubyte[] saveWater(ref World world) {
  foreach(coord; world.chunks.keys) {
    auto chunk = world.chunks[coord];
    world.data.waterDiffs.remove(chunk.coord);          // drop this chunk's stale snapshot
    foreach(idx; chunk.wetCells) {
      if(chunk.waterLevel[idx] > 0) world.data.waterDiffs[chunk.coord][cast(uint)idx] = chunk.waterLevel[idx];
    }
  }
  return flatten(world.data.waterDiffs);
}

/** Load waterDiffs from disk; chunks apply them at build, resident chunks applied immediately (mirrors rebuildDiffs). */
void loadWater(ref World world, Diff!ubyte[] flat) {
  world.data.waterDiffs = unflatten(flat);
  foreach(coord; world.chunks.keys) {  // apply to any already-resident chunks (newly-streamed ones get it in buildChunkData)
    if(auto wm = coord in world.data.waterDiffs) {
      auto chunk = world.chunks[coord];
      foreach(idx, lvl; *wm) {
        chunk.waterLevel[cast(int)idx] = lvl;
        chunk.wetCells ~= cast(int)idx;
        chunk.active ~= cast(int)idx;
        chunk.waterDirty = true;
      }
    }
  }
  SDL_Log("loadWater: %d cells", cast(int)flat.length);
}
