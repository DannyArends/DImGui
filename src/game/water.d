/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : faceData;
import gameobjects : WaterTiles;
import tile : tileBelow, tileCoord, tileIdx, tileToWorld, getWater, setWater;

enum ubyte WATER_MAX = 6;

alias WaterNext = ubyte[][int[3]];

/** Read level at any world tile from the next-buffer map (0 if unloaded / out of range). */
private int rdWater(ref GameApp app, ref WaterNext next, int[3] wc) {
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return 0;
  auto p = app.world.chunkCoord(wc) in next;
  return p is null ? 0 : (*p)[app.world.tileIdx(wc)];
}

/** Add delta at any world tile in the next-buffer map. Stops at edge of loaded world. */
private void wrWater(ref GameApp app, ref WaterNext next, int[3] wc, int delta) {
  auto p = app.world.chunkCoord(wc) in next;
  if(p is null) return;
  int idx = app.world.tileIdx(wc);
  (*p)[idx] = cast(ubyte)max(0, min(WATER_MAX, (*p)[idx] + delta));
}

/** One water simulation step over all loaded chunks. Spread then fall, crosses chunk boundaries. */
void waterTick(ref GameApp app) {
  // snapshot every loaded chunk's water into a world-addressable next-buffer map
  WaterNext next;
  foreach(coord; app.world.chunks.keys) next[coord] = app.world.chunks[coord].waterLevel.dup;
  static immutable int[2][4] H = [[1,0],[-1,0],[0,1],[0,-1]];

  // 1. SPREAD: excess (level > 1) random-walks toward the lowest neighbour(s)
  foreach(coord; app.world.chunks.keys) {
    ubyte[] cur = app.world.chunks[coord].waterLevel;
    foreach(i; 0 .. cast(int)cur.length) {
      if(cur[i] == 0) continue;
      int[3] wc = app.world.worldCoord(coord, app.world.tileCoord(i));
      int have = app.rdWater(next, wc);
      if(have <= 1) continue;                          // baseline 1s never spread

      // collect all holdable neighbours at the minimum level strictly below us
      int[3][4] best; int bestLvl = have; int n = 0;
      foreach(h; H) {
        int[3] nb = [wc[0]+h[0], wc[1], wc[2]+h[1]];
        if(!app.canHoldWater(nb)) continue;
        int nl = app.rdWater(next, nb);
        if(nl < bestLvl) { bestLvl = nl; best[0] = nb; n = 1; }        // new lowest -> reset list
        else if(nl == bestLvl && bestLvl < have) best[n++] = nb;       // tie at current lowest
      }
      if(n > 0) {
        int[3] dst = best[uniform(0, n)];               // random among equally-low neighbours
        app.wrWater(next, wc, -1);
        app.wrWater(next, dst, +1);
      }
    }
  }

  // 2. FALL: settle everything downward (incl. water that spread across a boundary)
  foreach(coord; app.world.chunks.keys) {
    ubyte[] buf = next[coord];
    foreach(i; 0 .. cast(int)buf.length) {
      if(buf[i] == 0) continue;
      int[3] wc = app.world.worldCoord(coord, app.world.tileCoord(i));
      int[3] below = wc.tileBelow;
      if(!app.canHoldWater(below)) continue;
      int move = min(app.rdWater(next, wc), WATER_MAX - app.rdWater(next, below));
      if(move > 0) {
        app.wrWater(next, wc, -move);
        app.wrWater(next, below, +move);
      }
    }
  }

  // 3. COMMIT only changed cells via setWater
  foreach(coord; app.world.chunks.keys) {
    ubyte[] buf = next[coord];
    ubyte[] old = app.world.chunks[coord].waterLevel;
    foreach(i; 0 .. cast(int)buf.length) {
      if(buf[i] == old[i]) continue;
      int[3] wc = app.world.worldCoord(coord, app.world.tileCoord(i));
      app.setWater(wc, buf[i]);
    }
  }
}

/** A cell can hold water if it is in range and air (not solid ground). */
private bool canHoldWater(ref GameApp app, int[3] wc) {
  import tile : getTileAt;
  if(wc[1] < 0 || wc[1] >= app.world.chunkHeight) return false;
  return app.world.getTileAt(wc) == ResourceType.None;
}

/** Rebuild water face instances for one chunk from its waterLevel. */
void rebuildChunkWater(ref GameApp app, Chunk chunk) {
  float ts = app.world.tileSize, th = app.world.tileHeight;
  DrawInstance[] inst;
  foreach(i; 0 .. cast(int)chunk.waterLevel.length) {
    ubyte lvl = chunk.waterLevel[i];
    if(lvl == 0) continue;
    int[3] wc = app.world.data.worldCoord(chunk.coord, app.world.data.tileCoord(i));
    float[3] p = app.world.data.tileToWorld(wc);
    float wh = th * (lvl / 6.0f);
    float cy = p[1] - th*0.5f + wh*0.5f;
    foreach(f; 0 .. 6){ inst ~= DrawInstance(cast(uint)ResourceType.Water, faceData(f, p[0], cy, p[2], ts, wh)); }
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