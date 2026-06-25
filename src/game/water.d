/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : faceData;
import gameobjects : WaterTiles;
import tile : tileBelow, tileCoord, tileIdx, tileToWorld, getWater, setWater;

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

  // collect active cells as world coords (only the cells in play; no full-volume dup)
  int[3][] act;
  foreach(coord; app.world.chunks.keys) {
    auto ch = app.world.chunks[coord];
    if(ch.wetCells.length == 0) continue;
    foreach(idx; ch.wetCells)
      if(ch.active[idx]) act ~= app.world.worldCoord(coord, app.world.tileCoord(idx));
  }
  if(act.length == 0) return;

  // 1. SPREAD
  foreach(wc; act) {
    int have = app.rdWater(next, wc);
    if(have <= 1) continue;
    int[3][4] best; int bestLvl = have; int n = 0;
    foreach(h; H) {
      int[3] nb = [wc[0]+h[0], wc[1], wc[2]+h[1]];
      if(!app.canHoldWater(nb)) continue;
      int nl = app.rdWater(next, nb);
      if(nl < bestLvl) { bestLvl = nl; best[0] = nb; n = 1; }
      else if(nl == bestLvl && bestLvl < have) best[n++] = nb;
    }
    if(n > 0) { int[3] dst = best[uniform(0, n)]; app.wrWater(next, touched, wc, -1); app.wrWater(next, touched, dst, +1); }
  }

  // 2. FALL
  foreach(wc; act) {
    int[3] below = wc.tileBelow;
    if(!app.canHoldWater(below)) continue;
    int move = min(app.rdWater(next, wc), WATER_MAX - app.rdWater(next, below));
    if(move > 0) { app.wrWater(next, touched, wc, -move); app.wrWater(next, touched, below, +move); }
  }

  // 3. COMMIT — only cells that actually changed; setWater re-activates them + neighbours
  foreach(wc, _; touched) {
    if(app.rdWater(next, wc) == app.getWater(wc)) continue;
    app.setWater(wc, cast(ubyte)next[wc]);
  }

  // 4. DEACTIVATE settled active cells
  foreach(wc; act) {
    if(!app.isSettled(wc)) continue;
    int[3] coord = app.world.chunkCoord(wc);
    if(coord !in app.world.chunks) continue;
    app.world.chunks[coord].active[app.world.tileIdx(wc)] = false;
  }
}

/** Lower one cell's water without waking the sim */
void evaporateTick(ref GameApp app) {
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    foreach(idx; chunk.wetCells.dup) {
      ubyte have = chunk.waterLevel[idx];
      if(have == 0 || have >= WATER_MAX) continue;
      if(uniform(0, 500) < (WATER_MAX - have) * 2) {
        int[3] wc = app.world.data.worldCoord(chunk.coord, app.world.data.tileCoord(idx));
        app.setWater(wc, cast(ubyte)(have - 1), false);
      }
    }
  }
}

/** Test if a cell is settled. */
private bool isSettled(ref GameApp app, int[3] wc) {
  int have = app.getWater(wc);
  if(have <= 0) return true;
  if(app.canHoldWater(wc.tileBelow) && app.getWater(wc.tileBelow) < WATER_MAX) return false; // can fall
  foreach(h; H) {
    int[3] nb = [wc[0]+h[0], wc[1], wc[2]+h[1]];
    if(app.canHoldWater(nb) && app.getWater(nb) < have) return false; // can spread
  }
  return true;
}

/** A cell can hold water if it is in range and air (not solid ground). */
private bool canHoldWater(ref GameApp app, int[3] wc) {
  import tile : getTileAt;
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return false;
  return app.world.getTileAt(wc) == ResourceType.None;
}

/** Rebuild the single world water object from all chunks' waterLevel. */
void rebuildWater(ref GameApp app) {
  if(app.world.water is null) return;
  float ts = app.world.tileSize, th = app.world.tileHeight;
  DrawInstance[] inst;
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    foreach(idx; chunk.wetCells) {
      ubyte lvl = chunk.waterLevel[idx];
      if(lvl == 0) continue;
      int[3] wc = app.world.data.worldCoord(chunk.coord, app.world.data.tileCoord(idx));
      float[3] p = app.world.data.tileToWorld(wc);
      float wh = th * (lvl / cast(float)WATER_MAX);
      float cy = p[1] - th*0.5f + wh*0.5f;
      foreach(f, nb; app.world.tileNeighbours(wc)) {
        if(app.getWater(nb) >= lvl) continue;
        inst ~= DrawInstance(cast(uint)ResourceType.Water, faceData(cast(int)f, p[0], cy, p[2], ts, wh));
      }
    }
  }
  app.world.water.instances = inst;
  app.world.water.instances.buffered = false;
}

/** If any chunk's water changed, rebuild the single water object. */
void flushWaterDirty(ref GameApp app) {
  bool any = false;
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    if(chunk.waterDirty) { chunk.waterDirty = false; any = true; }
  }
  if(any) app.rebuildWater();
}
