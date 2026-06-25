/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : faceData;
import tile : FACE_OFFSETS, tileBelow, tileCoord, tileIdx, tileToWorld, getWater, setWater;

enum ubyte WATER_MAX = 7;

static immutable int[2][4] H = [[1,0],[-1,0],[0,1],[0,-1]];

alias WaterNext    = ubyte[int[3]];     // world-cell -> pending level; absent = read committed
alias WaterTouched = bool[int[3]];      // world-cells written this tick (dedup set)

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

  struct Active { Chunk chunk; int idx; int[3] wc; }
  Active[] act;
  foreach(coord; app.world.chunks.keys) {
    auto ch = app.world.chunks[coord];
    if(ch.wetCells.length == 0) continue;
    foreach(idx; ch.wetCells)
      if(ch.active[idx]) act ~= Active(ch, idx, app.world.worldCoord(coord, app.world.tileCoord(idx)));
  }
  if(act.length == 0) return;

  // 1. SPREAD
  foreach(a; act) {
    int have = app.rdWater(next, a.wc);
    int[3][4] tgt;
    int n = app.spreadTargets(next, a.chunk, a.idx, a.wc, have, tgt);
    if(n > 0) { int[3] dst = tgt[uniform(0, n)]; app.wrWater(next, touched, a.wc, -1); app.wrWater(next, touched, dst, +1); }
  }

  // 2. FALL
  foreach(a; act) {
    if(!app.canFall(next, a.chunk, a.idx, a.wc)) continue;
    int[3] below = a.wc.tileBelow;
    int move = min(app.rdWater(next, a.wc), WATER_MAX - app.rdWater(next, below));
    if(move > 0) { app.wrWater(next, touched, a.wc, -move); app.wrWater(next, touched, below, +move); }
  }

  // 3. DEACTIVATE
  foreach(a; act) { if(app.isSettled(next, a.chunk, a.idx, a.wc)) a.chunk.active[a.idx] = false; }

  // 4. COMMIT
  foreach(wc, _; touched) {
    if(app.rdWater(next, wc) == app.getWater(wc)) continue;
    app.setWater(wc, cast(ubyte)next[wc]);
  }
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

/** Neighbour level: next-buffer if touched, else in-chunk direct read, else slow getWater. */
private int nbLevel(ref GameApp app, ref WaterNext next, Chunk chunk, int lx, int ly, int lz, int dx, int dy, int dz, int[3] base) {
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  int nx = lx+dx, ny = ly+dy, nz = lz+dz;
  int[3] nwc = [base[0]+dx, base[1]+dy, base[2]+dz];
  if(auto p = nwc in next) return *p;                       // pending write: must honour it
  if(nx>=0 && nx<S && ny>=0 && ny<Hh && nz>=0 && nz<S) return chunk.waterLevel[nz*Hh*S + ny*S + nx];
  return app.getWater(nwc);
}

private bool nbAir(ref GameApp app, Chunk chunk, int lx, int ly, int lz, int dx, int dy, int dz, int[3] base) {
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  int nx = lx+dx, ny = ly+dy, nz = lz+dz;
  if(ny < 0 || ny >= Hh) return false;
  if(nx>=0 && nx<S && nz>=0 && nz<S) return chunk.tileTypes[nz*Hh*S + ny*S + nx] == ResourceType.None;
  return app.canHoldWater([base[0]+dx, base[1]+dy, base[2]+dz]);
}

private int spreadTargets(ref GameApp app, ref WaterNext next, Chunk chunk, int idx, int[3] wc, int have, out int[3][4] tgt) {
  if(have < 2) return 0;
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  int lx = idx % S, ly = (idx / S) % Hh, lz = idx / (S*Hh);
  int bestLvl = have, n = 0;
  foreach(h; H) {
    if(!app.nbAir(chunk, lx, ly, lz, h[0], 0, h[1], wc)) continue;
    int nl = app.nbLevel(next, chunk, lx, ly, lz, h[0], 0, h[1], wc);
    int[3] nb = [wc[0]+h[0], wc[1], wc[2]+h[1]];
    if(nl < bestLvl) { bestLvl = nl; tgt[0] = nb; n = 1; }
    else if(nl == bestLvl && bestLvl < have) tgt[n++] = nb;
  }
  return n;
}

private bool canFall(ref GameApp app, ref WaterNext next, Chunk chunk, int idx, int[3] wc) {
  int S = app.world.chunkSize, Hh = app.world.chunkHeight;
  int lx = idx % S, ly = (idx / S) % Hh, lz = idx / (S*Hh);
  if(!app.nbAir(chunk, lx, ly, lz, 0, -1, 0, wc)) return false;
  return app.nbLevel(next, chunk, lx, ly, lz, 0, -1, 0, wc) < WATER_MAX;
}

private bool isSettled(ref GameApp app, ref WaterNext next, Chunk chunk, int idx, int[3] wc) {
  int have = app.rdWater(next, wc);
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
      int nx = lx+FACE_OFFSETS[f][0], ny = ly+FACE_OFFSETS[f][1], nz = lz+FACE_OFFSETS[f][2];
      int nlvl;
      if(nx>=0 && nx<S && ny>=0 && ny<Hh && nz>=0 && nz<S){
        nlvl = chunk.waterLevel[nz*Hh*S + ny*S + nx];
      }else{ nlvl = app.getWater(app.world.data.worldCoord(chunk.coord, [nx, ny, nz])); }
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
    if(chunk.waterDirty) { app.rebuildChunkWaterInstances(chunk); chunk.waterDirty = false; any = true; }
  }
  if(!any || app.world.water is null) return;
  DrawInstance[] all;
  foreach(coord; app.world.chunks.keys) all ~= app.world.chunks[coord].waterInstances;  // concat cached
  app.world.water.instances = all;
  app.world.water.instances.buffered = false;
}
