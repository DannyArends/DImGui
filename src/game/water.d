/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import tile : tileBelow, tileCoord, tileIdx, getWater, setWater;

enum ubyte WATER_MAX = 6;

/** One water simulation step over all loaded chunks. Double-buffered: reads current, writes next. */
void waterTick(ref GameApp app) {
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    ubyte[] cur = chunk.waterLevel;
    ubyte[] next = cur.dup;                       // write target
    bool changed = false;

    foreach(i; 0 .. cast(int)cur.length) {
      if(cur[i] == 0) continue;                   // no water here
      int[3] local = app.world.tileCoord(i);
      int[3] wc = app.world.worldCoord(coord, local);

      ubyte have = cur[i];

      // 1. FALL: push down if the cell below is air and not full
      int[3] below = wc.tileBelow;
      if(app.canHoldWater(below)) {
        int room = WATER_MAX - app.getWaterNext(chunk, next, below);
        int move = min(cast(int)have, room);
        if(move > 0) {
          SDL_Log(cstr("FALL [%d,%d,%d] have=%d -> below [%d,%d,%d] move=%d", wc[0],wc[1],wc[2], have, below[0],below[1],below[2], move));
          addNext(app, chunk, next, wc, -move);
          addNext(app, chunk, next, below, move);
          have -= cast(ubyte)move;
          changed = true;
          if(have == 0) continue;
        }
      }

      // 2. SPREAD: equalize with the 4 horizontal neighbours that are lower
      static immutable int[2][4] H = [[1,0],[-1,0],[0,1],[0,-1]];
      foreach(h; H) {
        int[3] nb = [wc[0]+h[0], wc[1], wc[2]+h[1]];
        if(!app.canHoldWater(nb)) continue;
        int nl = app.getWaterNext(chunk, next, nb);
        int diff = have - nl;
        if(diff >= 2) {                           // only flow if >=2 apart (avoids 1<->0 oscillation)
          SDL_Log(cstr("SPREAD [%d,%d,%d] -> [%d,%d,%d] diff=%d", wc[0],wc[1],wc[2], nb[0],nb[1],nb[2], diff));
          addNext(app, chunk, next, wc, -1);
          addNext(app, chunk, next, nb, 1);
          have -= 1;
          changed = true;
        }
      }
    }

    if(changed) { chunk.waterLevel = next; chunk.waterDirty = true; }
    int wet = 0; foreach(v; chunk.waterLevel) if(v > 0) wet++;
    if(wet > 0) SDL_Log(cstr("waterTick: chunk=[%d,%d,%d] wet=%d changed=%d", coord[0], coord[1], coord[2], wet, changed));
  }
}

/** A cell can hold water if it is in this chunk, in range, and air (not solid ground) */
private bool canHoldWater(ref GameApp app, int[3] wc) {
  import tile : getTileAt;
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return false;
  return app.world.getTileAt(wc) == ResourceType.None;
}

/** Read the next-buffer level at wc IF it belongs to this chunk; else fall back to committed getWater (cross-chunk = read-only for v1) */
private int getWaterNext(ref GameApp app, Chunk chunk, ubyte[] next, int[3] wc) {
  if(app.world.chunkCoord(wc) == chunk.coord) return next[app.world.tileIdx(wc)];
  return app.getWater(wc);     // neighbouring chunk: read current, don't write (v1 scope)
}

/** Add delta to the next-buffer at wc IF it belongs to this chunk (skip cross-chunk writes for v1) */
private void addNext(ref GameApp app, Chunk chunk, ubyte[] next, int[3] wc, int delta) {
  if(app.world.chunkCoord(wc) != chunk.coord) return;   // v1: water stops at chunk edges
  int idx = app.world.tileIdx(wc);
  int v = next[idx] + delta;
  next[idx] = cast(ubyte)max(0, min(WATER_MAX, v));
}