/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : faceData;
import tile : FACE_OFFSETS, neighbourCell, tileBelow, tileCoord, tileIdx, tileToWorld, getWater, setWater;

enum ubyte WATER_MAX = 7;

static immutable int[2][4] H = [[1,0],[-1,0],[0,1],[0,-1]];

alias WaterNext    = ubyte[int[3]];     // world-cell -> pending level; absent = read committed
alias WaterTouched = bool[int[3]];      // world-cells written this tick (dedup set)

/** This cell's pending level: next-buffer if touched, else direct array read (no getWater hash). */
private int ownLevel(ref WaterNext next, Chunk chunk, int idx, int[3] wc) {
  auto p = wc in next;
  return p is null ? chunk.waterLevel[idx] : *p;
}

/** Read pending level at a world tile: next-buffer if present, else committed getWater. */
private int rdWater(ref GameApp app, ref WaterNext next, int[3] wc) {
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return 0;
  auto p = wc in next;
  return p is null ? app.getWater(wc) : *p;
}

/** Apply delta to a world tile in the sparse next-buffer; records it touched.
    Seeds from committed level on first write so we never need a full dup. */
private void wrWater(ref GameApp app, ref WaterNext next, ref WaterTouched touched, int[3] wc, int delta) {
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return;
  if(app.world.chunkCoord(wc) !in app.world.chunks) return;   // edge of loaded world: drop
  auto p = wc in next;
  int cur = p is null ? app.getWater(wc) : *p;
  next[wc] = cast(ubyte)max(0, min(WATER_MAX, cur + delta));
  touched[wc] = true;
}

/** One water simulation step. Spread then fall, crosses chunk boundaries. Iterates only wet cells. */
void waterTick(ref GameApp app) {
  WaterNext next;
  WaterTouched touched;
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  ulong t;

  struct Active { Chunk chunk; int idx; int[3] wc; }
  Active[] act;

  // PHASE 1: GATHER
  t = SDL_GetTicks();
  foreach(coord; app.world.chunks.keys) {
    auto ch = app.world.chunks[coord];
    if(ch.wetCells.length == 0) continue;
    foreach(idx; ch.wetCells)
      if(ch.active[idx]) act ~= Active(ch, idx, app.world.worldCoord(coord, app.world.tileCoord(idx)));
  }
  debug app.timings["waterGather"] = SDL_GetTicks() - t;
  if(act.length == 0) return;

  bool[] moved; moved.length = act.length;

  // PHASE 2: SPREAD
  t = SDL_GetTicks();
  foreach(i, a; act) {
    int have = ownLevel(next, a.chunk, a.idx, a.wc);
    int[3][4] tgt;
    int n = app.spreadTargets(next, a.chunk, a.idx, a.wc, have, tgt);
    if(n > 0) { int[3] dst = tgt[uniform(0, n)]; app.wrWater(next, touched, a.wc, -1); app.wrWater(next, touched, dst, +1); moved[i] = true; }
  }
  debug app.timings["waterSpread"] = SDL_GetTicks() - t;

  // PHASE 3: FALL
  t = SDL_GetTicks();
  foreach(i, a; act) {
    if(!app.canFall(next, a.chunk, a.idx, a.wc)) continue;
    int[3] below = a.wc.tileBelow;
    int mv = min(ownLevel(next, a.chunk, a.idx, a.wc), WATER_MAX - app.rdWater(next, below));
    if(mv > 0) { app.wrWater(next, touched, a.wc, -mv); app.wrWater(next, touched, below, +mv); moved[i] = true; }
  }
  debug app.timings["waterFall"] = SDL_GetTicks() - t;

  // PHASE 4: COMMIT changed cells
  t = SDL_GetTicks();
  foreach(wc, _; touched) {
    if(app.rdWater(next, wc) == app.getWater(wc)) continue;
    app.setWater(wc, cast(ubyte)next[wc]);
  }
  debug app.timings["waterCommit"] = SDL_GetTicks() - t;

  // PHASE 5: DEACTIVATE: unmoved cells MIGHT be settled — confirm before deactivating
  t = SDL_GetTicks();
  foreach(i, a; act) {
    if(moved[i]) continue; // moved -> definitely active
    if(app.isSettled(next, a.chunk, a.idx, a.wc)){ a.chunk.active[a.idx] = false; }
  }
  debug app.timings["waterDeactivate"] = SDL_GetTicks() - t;
}

/** Lower one cell's water without waking the sim */
void evaporateTick(ref GameApp app) {
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    foreach(idx; chunk.wetCells.dup) {
      ubyte have = chunk.waterLevel[idx];
      if(have == 0 || have >= (WATER_MAX/2)) continue;
      if(uniform(0, 5000) < (WATER_MAX - have) * 2) {
        int[3] wc = app.world.data.worldCoord(chunk.coord, app.world.data.tileCoord(idx));
        app.setWater(wc, cast(ubyte)(have - 1), false);
      }
    }
  }
}

private int spreadTargets(ref GameApp app, ref WaterNext next, Chunk chunk, int idx, int[3] wc, int have, out int[3][4] tgt) {
  if(have < 2) return 0;
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  int lx = idx % S, ly = (idx / S) % Hh, lz = idx / (S*Hh);
  int bestLvl = have, n = 0;
  foreach(h; H) {
    Chunk nch; int nidx;
    if(!app.neighbourCell(chunk, lx, ly, lz, h[0], 0, h[1], nch, nidx)) continue;   // resolve ONCE
    if(nch.tileTypes[nidx] != ResourceType.None) continue;                          // air check (direct)
    int[3] nwc = [wc[0]+h[0], wc[1], wc[2]+h[1]];
    auto p = nwc in next;                                                           // pending?
    int nl = p is null ? nch.waterLevel[nidx] : *p;                                 // level (direct or pending)
    if(nl < bestLvl) { bestLvl = nl; tgt[0] = nwc; n = 1; }
    else if(nl == bestLvl && bestLvl < have) tgt[n++] = nwc;
  }
  return n;
}

private bool canFall(ref GameApp app, ref WaterNext next, Chunk chunk, int idx, int[3] wc) {
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  int lx = idx % S, ly = (idx / S) % Hh, lz = idx / (S*Hh);
  Chunk nch; int nidx;
  if(!app.neighbourCell(chunk, lx, ly, lz, 0, -1, 0, nch, nidx)) return false;
  if(nch.tileTypes[nidx] != ResourceType.None) return false;       // not air
  int[3] bwc = [wc[0], wc[1]-1, wc[2]];
  auto p = bwc in next;
  int bl = p is null ? nch.waterLevel[nidx] : *p;
  return bl < WATER_MAX;
}

private bool isSettled(ref GameApp app, ref WaterNext next, Chunk chunk, int idx, int[3] wc) {
  int have = ownLevel(next, chunk, idx, wc);
  if(have <= 0) return true;
  if(app.canFall(next, chunk, idx, wc)) return false;
  int[3][4] tgt;
  if(app.spreadTargets(next, chunk, idx, wc, have, tgt) > 0) return false;
  return true;
}

/** A cell can hold water if it is in range and air (not solid ground). */
private bool canHoldWater(ref GameApp app, int[3] wc) {
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return false;
  auto p = app.world.chunkCoord(wc) in app.world.chunks;
  if(p is null) return false;                              // unloaded -> can't hold (edge of world)
  return (*p).tileTypes[app.world.tileIdx(wc)] == ResourceType.None;
}

/** Rebuild the single world water object from all chunks' waterLevel. */
private void rebuildChunkWaterInstances(ref GameApp app, Chunk chunk) {
  float ts = app.world.tileSize, th = app.world.tileHeight;
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  DrawInstance[] inst;
  foreach(idx; chunk.wetCells) {
    ubyte lvl = chunk.waterLevel[idx];
    if(lvl == 0) continue;
    int lx = idx % S, ly = (idx / S) % Hh, lz = idx / (S*Hh);
    int[3] wc = app.world.data.worldCoord(chunk.coord, [lx, ly, lz]);
    float[3] p = app.world.data.tileToWorld(wc);
    float wh = th * (lvl / cast(float)WATER_MAX);
    float cy = p[1] - th*0.5f + wh*0.5f;
    foreach(f; 0 .. 6) {
      Chunk nch; int nidx;
      int nlvl = app.neighbourCell(chunk, lx, ly, lz, FACE_OFFSETS[f][0], FACE_OFFSETS[f][1], FACE_OFFSETS[f][2], nch, nidx)? nch.waterLevel[nidx] : 0;
      if(nlvl >= lvl) continue;
      inst ~= DrawInstance(cast(uint)ResourceType.Water, faceData(f, p[0], cy, p[2], ts, wh));
    }
  }
  chunk.waterInstances = inst;
}

/** If any chunk's water changed, rebuild the single water object. */
void flushWaterDirty(ref GameApp app) {
  bool any = false;
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    if(!chunk.waterDirty) continue;
    if(!chunk.tiles.inFrustum) continue;  // skip off-screen: defer re-mesh until visible
    app.rebuildChunkWaterInstances(chunk);
    chunk.waterDirty = false;  // cleared only when actually re-meshed
    any = true;
  }
  if(!any || app.world.water is null) return;
  DrawInstance[] all;
  foreach(coord; app.world.chunks.keys) all ~= app.world.chunks[coord].waterInstances;
  app.world.water.instances = all;
  app.world.water.instances.buffered = false;
}
