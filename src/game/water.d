/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : faceData;
import clouds : CLOUD_STEP, cloudCell;
import serialization : readData, writeData;
import tile : FACE_OFFSETS, neighbourAt, tileBelow, tileCoord, tileIdx, tileToWorld, getWater, setWater;

enum ubyte WATER_MAX = 7;               // Maximum water density
enum int WATER_TARGET_ACTIVE = 1250;    // Desired number of live water cells in sim
enum float EVAP_DENSITY = 0.005f;       // Density added through water evaporation
enum uint EVAP_DEPLETE = 3000;          // Speed of evaporation

static immutable int[2][4] H = [[1,0],[-1,0],[0,1],[0,-1]];

/** Persisted water cell: world-coord + level, serialised in the water save file. */
struct WaterDiff { int[3] coord; uint idx; ubyte level; }
/** An active cell queued for this tick's simulation: its chunk, local index, and world-coord. */
struct Active { Chunk chunk; int idx; int[3] wc; }

alias WaterNext = ubyte[int[3]];        // world-cell -> pending level; absent = read committed
alias WaterTouched = bool[int[3]];      // world-cells written this tick (dedup set)

/** This cell's pending level: next-buffer if touched, else direct array read (no getWater hash). */
private @nogc int ownLevel(const WaterNext next, const Chunk chunk, int idx, const int[3] wc) nothrow {
  auto p = wc in next;
  return p is null ? chunk.waterLevel[idx] : *p;
}

/** Read pending level at a world tile: next-buffer if present, else committed getWater. */
private @nogc int rdWater(ref GameApp app, const WaterNext next, const int[3] wc) nothrow {
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return 0;
  auto p = wc in next;
  return p is null ? app.getWater(wc) : *p;
}

@nogc activeSim(const Chunk[int[3]] chunks) {
  int active = 0;
  foreach(c; chunks){ active += cast(int)c.active.length; }
  return(active);
}

/** Apply delta to a world tile in the sparse next-buffer; records it touched.
    Seeds from committed level on first write so we never need a full dup. */
private void wrWater(ref GameApp app, ref WaterNext next, ref WaterTouched touched, int[3] wc, int delta) {
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return;
  if(app.world.chunkCoord(wc) !in app.world.chunks) return;
  int cur = app.rdWater(next, wc);
  next[wc] = cast(ubyte)max(0, min(WATER_MAX, cur + delta));
  touched[wc] = true;
}

/** One water simulation step. Spread then fall, crosses chunk boundaries. Iterates only wet cells. */
void waterTick(ref GameApp app) {
  WaterNext next;
  WaterTouched touched;
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  ulong t;

  Active[] act;

  // PHASE 1: GATHER
  foreach(coord; app.world.chunks.keys) {
    auto ch = app.world.chunks[coord];
    if(ch.active.length == 0) continue;
    foreach(idx; ch.active){ act ~= Active(ch, idx, app.world.worldCoord(coord, app.world.tileCoord(idx))); }
  }
  if(act.length == 0) return;

  bool[] moved; moved.length = act.length;

  // PHASE 2: SPREAD
  foreach(i, a; act) {
    int have = ownLevel(next, a.chunk, a.idx, a.wc);
    int[3][4] tgt;
    int n = app.world.spreadTargets(next, a.chunk, a.idx, a.wc, have, tgt);
    if(n > 0) { int[3] dst = tgt[uniform(0, n)]; app.wrWater(next, touched, a.wc, -1); app.wrWater(next, touched, dst, +1); moved[i] = true; }
  }

  // PHASE 3: FALL
  foreach(i, a; act) {
    if(!app.world.canFall(next, a.chunk, a.idx, a.wc)) continue;
    int[3] below = a.wc.tileBelow;
    int mv = min(ownLevel(next, a.chunk, a.idx, a.wc), WATER_MAX - app.rdWater(next, below));
    if(mv > 0) { app.wrWater(next, touched, a.wc, -mv); app.wrWater(next, touched, below, +mv); moved[i] = true; }
  }

  // PHASE 4: COMMIT changed cells
  foreach(wc, _; touched) {
    if(app.rdWater(next, wc) == app.getWater(wc)) continue;
    app.setWater(wc, cast(ubyte)next[wc]);
  }

  // PHASE 5: DEACTIVATE: unmoved cells MIGHT be settled — confirm before deactivating
  foreach(i, a; act) {
    if(moved[i]) continue; // moved -> definitely active
    if(app.world.isSettled(next, a.chunk, a.idx, a.wc)){ a.chunk.active.remove(a.idx); }
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
        app.setWater(wc, cast(ubyte)(chunk.waterLevel[idx] - 1), false);
        auto cell = cloudCell(wc[0], wc[2]);
        auto dd = H[uniform(0, 4)];
        app.world.cloudDensity[[cell[0] + dd[0], cell[1] + dd[1]]] += uniform(1, hi) * EVAP_DENSITY;   // moisture rises and drifts to a neighbour
      }
    }
  }
}

/** Collect the lowest-level air neighbours water could spread into (4-connected, horizontal).
    Returns the count and fills `tgt` with up to 4 equally-low targets strictly below `have`;
    0 if the cell holds < 2 or no neighbour is lower. Reads pending levels from `next`. */
private int spreadTargets(const World world, const WaterNext next, const Chunk chunk, int idx, int[3] wc, int have, out int[3][4] tgt) nothrow {
  if(have < 2) return 0;
  auto lc = world.tileCoord(idx);
  int bestLvl = have, n = 0;
  foreach(h; H) {
    int[3] nc; int nidx;
    if(!world.neighbourAt(chunk.coord, lc, [h[0], 0, h[1]], nc, nidx)) continue;
    auto nch = (nc == chunk.coord) ? chunk : world.chunks[nc];
    if(nch.tileTypes[nidx] != ResourceType.None) continue;
    int[3] nwc = [wc[0]+h[0], wc[1], wc[2]+h[1]];
    auto p = nwc in next;                                                           // pending?
    int nl = p is null ? nch.waterLevel[nidx] : *p;                                 // level (direct or pending)
    if(nl < bestLvl) { bestLvl = nl; tgt[0] = nwc; n = 1; 
    }else if(nl == bestLvl && bestLvl < have){ tgt[n++] = nwc; }
  }
  return n;
}

/** True if the cell below is air and not yet full, so water here can fall into it. */
private bool canFall(const World world, const WaterNext next, const Chunk chunk, int idx, int[3] wc) nothrow {
  auto lc = world.tileCoord(idx);
  int[3] nc; int nidx;
  if(!world.neighbourAt(chunk.coord, lc, [0,-1,0], nc, nidx)) return false;
  auto nch = (nc == chunk.coord) ? chunk : world.chunks[nc];
  if(nch.tileTypes[nidx] != ResourceType.None) return false;
  auto p = tileBelow(wc) in next;
  int bl = (p is null) ? nch.waterLevel[nidx] : *p;
  return bl < WATER_MAX;
}

/** True if the cell has water but can neither fall nor spread - i.e. nothing left to simulate this tick. */
private bool isSettled(const World world, const WaterNext next, const Chunk chunk, int idx, int[3] wc) nothrow {
  int have = ownLevel(next, chunk, idx, wc);
  if(have <= 0) return(true);
  if(world.canFall(next, chunk, idx, wc)) return(false);
  int[3][4] tgt;
  if(world.spreadTargets(next, chunk, idx, wc, have, tgt) > 0) return(false);
  return(true);
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
      inst ~= DrawInstance(cast(uint)ResourceType.Water, faceData(f, p[0], cy, p[2], world.tileSize, wh));
    }
  }
  return(inst);
}

/** If any chunk's water changed, rebuild the single water object. */
void flushWaterDirty(ref GameApp app) {
  bool any = false;
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    if(!chunk.waterDirty) continue;
    if(!chunk.tiles.inFrustum) continue;  // skip off-screen: defer re-mesh until visible
    chunk.waterInstances = app.world.rebuildChunkWaterInstances(chunk);
    chunk.waterDirty = false;  // cleared only when actually re-meshed
    any = true;
  }
  if(!any || app.world.water is null) return;
  DrawInstance[] all;
  foreach(coord; app.world.chunks.keys) all ~= app.world.chunks[coord].waterInstances;
  app.world.water.instances = all;
  app.world.water.instances.invalidate();
  if(app.world.water.box !is null) app.world.water.box.dirty = true;
}

/** Snapshot all loaded chunks' water into waterDiffs, then flatten + save (mirrors saveDiffs). */
void saveWater(ref World world) {
  foreach(coord; world.chunks.keys) {
    auto chunk = world.chunks[coord];
    world.data.waterDiffs.remove(chunk.coord);          // drop this chunk's stale snapshot
    foreach(idx; chunk.wetCells) {
      if(chunk.waterLevel[idx] > 0) world.data.waterDiffs[chunk.coord][cast(uint)idx] = chunk.waterLevel[idx];
    }
  }
  WaterDiff[] flat;
  foreach(coord, idxMap; world.data.waterDiffs){ foreach(idx, lvl; idxMap){ flat ~= WaterDiff(coord, idx, lvl); } }
  if(flat.length == 0) { SDL_RemovePath(world.waterPath()); return; }
  writeData(world.waterPath(), flat, cast(uint)flat.length);
}

/** Load waterDiffs from disk; chunks apply them at build, resident chunks applied immediately (mirrors rebuildDiffs). */
void loadWater(ref World world) {
  WaterDiff[] flat;
  uint h;
  if(!readData(world.waterPath(), flat, h)) return;
  world.data.waterDiffs = null;
  foreach(ref d; flat){ world.data.waterDiffs[d.coord][d.idx] = d.level; }
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
