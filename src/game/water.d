/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : faceData;
import gameobjects : WaterTiles;
import tile : tileBelow, tileCoord, tileIdx, tileToWorld, getWater, setWater;

enum ubyte WATER_MAX = 6;

alias WaterNext    = ubyte[][int[3]];
alias WaterTouched = int[][int[3]];                        // per-chunk list of touched local indices

/** Read level at any world tile from the next-buffer map (0 if unloaded / out of range). */
private int rdWater(ref GameApp app, ref WaterNext next, int[3] wc) {
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return 0;
  auto p = app.world.chunkCoord(wc) in next;
  return p is null ? 0 : (*p)[app.world.tileIdx(wc)];
}

/** Add delta at any world tile in the next-buffer map; records the touched cell. Stops at edge of loaded world. */
private void wrWater(ref GameApp app, ref WaterNext next, ref WaterTouched touched, int[3] wc, int delta) {
  int[3] cc = app.world.chunkCoord(wc);
  auto p = cc in next;
  if(p is null) return;
  int idx = app.world.tileIdx(wc);
  (*p)[idx] = cast(ubyte)max(0, min(WATER_MAX, (*p)[idx] + delta));
  touched[cc] ~= idx;                                      // duplicates harmless (setWater no-ops on unchanged)
}

/** One water simulation step. Spread then fall, crosses chunk boundaries. Iterates only wet cells. */
void waterTick(ref GameApp app) {
  WaterNext next;
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    if(chunk.activeCells.length == 0) continue;             // dormant chunk: skip entirely
    next[coord] = chunk.waterLevel.dup;
  }
  WaterTouched touched;
  static immutable int[2][4] H = [[1,0],[-1,0],[0,1],[0,-1]];

  // process only ACTIVE cells (snapshot the lists; setWater will rebuild activeCells for next tick)
  int[][int[3]] active;
  foreach(coord, _; next) { 
    active[coord] = app.world.chunks[coord].activeCells.sort.uniq.array;
    app.world.chunks[coord].activeCells = [];
  }

  // 1. SPREAD
  foreach(coord, idxs; active) {
    foreach(idx; idxs) {
      int[3] wc = app.world.worldCoord(coord, app.world.tileCoord(idx));
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
  }

  // 2. FALL
  foreach(coord, idxs; active) {
    foreach(idx; idxs) {
      int[3] wc = app.world.worldCoord(coord, app.world.tileCoord(idx));
      int[3] below = wc.tileBelow;
      if(!app.canHoldWater(below)) continue;
      int move = min(app.rdWater(next, wc), WATER_MAX - app.rdWater(next, below));
      if(move > 0) { app.wrWater(next, touched, wc, -move); app.wrWater(next, touched, below, +move); }
    }
  }

  // 3. EVAPORATE: water below full has a chance to lose a unit (shallower = faster)
  foreach(coord, idxs; active) {
    foreach(idx; idxs) {
      int[3] wc = app.world.worldCoord(coord, app.world.tileCoord(idx));
      int have = app.rdWater(next, wc);
      if(have <= 0 || have >= WATER_MAX) continue;
      app.world.chunks[coord].activeCells ~= idx;
      if(uniform(0, 1000) < (WATER_MAX - have) * 2){ app.wrWater(next, touched, wc, -1); }
    }
  }

  // 4. COMMIT — setWater re-activates changed cells + neighbours for next tick
  foreach(coord, idxs; touched) {
    ubyte[] old = app.world.chunks[coord].waterLevel;
    ubyte[] buf = next[coord];
    foreach(i; idxs) {
      if(buf[i] == old[i]) continue;
      int[3] wc = app.world.worldCoord(coord, app.world.tileCoord(i));
      app.setWater(wc, cast(ubyte)buf[i]);                  // -> activate(wc) repopulates activeCells
    }
  }
}

/** A cell can hold water if it is in range and air (not solid ground). */
private bool canHoldWater(ref GameApp app, int[3] wc) {
  import tile : getTileAt;
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return false;
  return app.world.getTileAt(wc) == ResourceType.None;
}

/** Rebuild water face instances for one chunk; emits only faces exposed to air / lower water. */
void rebuildChunkWater(ref GameApp app, Chunk chunk) {
  static immutable int[3][6] N = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
  float ts = app.world.tileSize, th = app.world.tileHeight;
  DrawInstance[] inst;
  inst.reserve(chunk.wetCells.length * 2);
  foreach(idx; chunk.wetCells) {
    ubyte lvl = chunk.waterLevel[idx];
    if(lvl == 0) continue;
    int[3] wc = app.world.data.worldCoord(chunk.coord, app.world.data.tileCoord(idx));
    float[3] p = app.world.data.tileToWorld(wc);
    float wh = th * (lvl / 6.0f);
    float cy = p[1] - th*0.5f + wh*0.5f;
    foreach(f; 0 .. 6) {
      int[3] nb = [wc[0]+N[f][0], wc[1]+N[f][1], wc[2]+N[f][2]];
      if(app.getWater(nb) >= lvl) continue;                // hidden by equal/higher water neighbour
      inst ~= DrawInstance(cast(uint)ResourceType.Water, faceData(f, p[0], cy, p[2], ts, wh));
    }
  }
  chunk.water.instances = inst;
  chunk.water.instances.buffered = false;
  chunk.waterDirty = false;
}

/** Re-mesh any chunk whose water changed this frame. */
void flushWaterDirty(ref GameApp app) {
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    if(chunk.waterDirty) app.rebuildChunkWater(chunk);
  }
}
