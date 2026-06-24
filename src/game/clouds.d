/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import noise : smoothNoise;
import gameobjects : Clouds;
import chunk : faceData;

enum int CLOUD_LAYERS = 8;
enum int CLOUD_STEP = 6;
enum float CLOUD_THRESHOLD = 0.75f;
enum float CLOUD_FREQ = 0.08f;

private bool isCloud(int tx, int y, int tz) {
  if(y < 0 || y >= CLOUD_LAYERS) return false;
  float fy = (y - (CLOUD_LAYERS-1)*0.5f) / (CLOUD_LAYERS*0.5f);
  float d = smoothNoise([tx*CLOUD_FREQ, y*0.6f, tz*CLOUD_FREQ], 1337) * (1.0f - fy*fy*0.7f);
  return d >= CLOUD_THRESHOLD;
}

void rebuildClouds(ref GameApp app) {
  if(app.world.clouds is null) return;
  float ts = app.world.tileSize, th = app.world.tileHeight;
  int cs = app.world.chunkSize;
  float baseY = app.world.height + 8.0f * th;
  float vox = CLOUD_STEP * ts, voxH = th * CLOUD_STEP;

  // neighbour offsets in (x,y,z) matching faceData's f = 0..5 ordering
  static immutable int[3][6] N = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];

  DrawInstance[] inst;
  foreach(coord; app.world.chunks.keys) {
    int baseX = coord[0] * cs, baseZ = coord[2] * cs;
    for(int lz = 0; lz < cs; lz += CLOUD_STEP)
    for(int lx = 0; lx < cs; lx += CLOUD_STEP) {
      // grid index in "cloud-cell" space so neighbours are ±1 cell
      int gx = (baseX + lx) / CLOUD_STEP;
      int gz = (baseZ + lz) / CLOUD_STEP;
      foreach(y; 0 .. CLOUD_LAYERS) {
        if(!isCloud(gx, y, gz)) continue;
        float px = (baseX + lx) * ts, py = baseY + y*voxH, pz = (baseZ + lz) * ts;
        foreach(f; 0 .. 6) {
          if(isCloud(gx + N[f][0], y + N[f][1], gz + N[f][2])) continue;  // neighbour present -> face hidden
          inst ~= DrawInstance(cast(uint)ResourceType.Ice01, faceData(f, px, py, pz, vox, voxH));
        }
      }
    }
  }
  app.world.clouds.instances = inst;
  app.world.clouds.instances.buffered = false;
}
