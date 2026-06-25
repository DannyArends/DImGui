/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock;
import chunk : faceData;
import gameobjects : Clouds;
import noise : smoothNoise;
import tile : FACE_OFFSETS, getWater, setWater, getTileAt;
import water : WATER_MAX;

enum int CLOUD_LAYERS = 8;              // Layers
enum int CLOUD_STEP = 6;                // Step
enum float CLOUD_THRESHOLD = 0.80f;     // Threshold
enum float CLOUD_FREQ = 0.06f;          // frequency
enum int RAIN_DROPS_PER_TICK = 250;     // sparse
enum float RAIN_DEPLETE = 0.001f;       // density removed from a cloud cell per drop spawned
enum float EVAP_DENSITY = 0.0005f;      

private bool isCloud(ref GameApp app, int gx, int y, int gz) {
  if(y < 0 || y >= CLOUD_LAYERS) return false;
  float fy = (y - (CLOUD_LAYERS-1)*0.5f) / (CLOUD_LAYERS*0.5f);
  float d = smoothNoise([gx*CLOUD_FREQ, y*0.6f, gz*CLOUD_FREQ], 1337) * (1.0f - fy*fy*0.7f);
  if(auto p = [gx, gz] in app.world.cloudDensity) d += *p;
  return d >= CLOUD_THRESHOLD;
}

void rebuildClouds(ref GameApp app) {
  if(app.world.clouds is null) return;
  float ts = app.world.tileSize, th = app.world.tileHeight;
  int cs = app.world.chunkSize;
  float baseY = app.world.height + 8.0f * th;
  float vox = CLOUD_STEP * ts, voxH = th * CLOUD_STEP;

  DrawInstance[] inst;
  foreach(coord; app.world.chunks.keys) {
    int baseX = coord[0] * cs, baseZ = coord[2] * cs;
    for(int lz = 0; lz < cs; lz += CLOUD_STEP)
    for(int lx = 0; lx < cs; lx += CLOUD_STEP) {
      // grid index in "cloud-cell" space so neighbours are ±1 cell
      int gx = (baseX + lx) / CLOUD_STEP;
      int gz = (baseZ + lz) / CLOUD_STEP;
      foreach(y; 0 .. CLOUD_LAYERS) {
        if(!app.isCloud(gx, y, gz)) continue;
        float px = (baseX + lx) * ts, py = baseY + y*voxH, pz = (baseZ + lz) * ts;
        foreach(f; 0 .. 6) {
          if(app.isCloud(gx + FACE_OFFSETS[f][0], y + FACE_OFFSETS[f][1], gz + FACE_OFFSETS[f][2])) continue;
          inst ~= DrawInstance(cast(uint)ResourceType.Ice01, faceData(f, px, py, pz, vox, voxH));
        }
      }
    }
  }
  app.world.clouds.instances = inst;
  app.world.clouds.instances.buffered = false;
}

void rainTick(ref GameApp app) {
  auto coords = app.world.chunks.keys;
  if(coords.length == 0) return;
  int cs = app.world.chunkSize;
  int cloudY = app.world.chunkHeight - 1;   // spawn near top of world (under cloud layer)

  foreach(_; 0 .. RAIN_DROPS_PER_TICK) {
    int[3] cc = coords[uniform(0, coords.length)];
    int lx = uniform(0, cs), lz = uniform(0, cs);
    int tx = cc[0]*cs + lx, tz = cc[2]*cs + lz;

    bool cloudAbove = false;
    foreach(cy; 0 .. CLOUD_LAYERS) if(app.isCloud(tx/CLOUD_STEP, cy, tz/CLOUD_STEP)) { cloudAbove = true; break; }
    if(!cloudAbove) continue;

    int[3] spawn = [tx, cloudY, tz];
    if(app.world.getTileAt(spawn) != ResourceType.None) continue;   // need air to spawn into
    uint id = app.spawnBlock(spawn, ResourceType.Water);
    if(auto b = id in app.world.blocks) { b.fall.weight = 20.0f; b.fall.start(app.world, spawn, -app.world.blockOffset); }
    app.world.cloudDensity[[tx/CLOUD_STEP, tz/CLOUD_STEP]] -= RAIN_DEPLETE;   // raining thins the cloud
  }
}

/** Convert any landed rain (Water blocks no longer falling) into water level. */
void settleRain(ref GameApp app) {
  uint[] done;
  foreach(id, ref b; app.world.blocks) {
    if(b.type != ResourceType.Water) continue;
    if(b.isFalling) continue;                 // still in the air
    app.setWater(b.tile, cast(ubyte)min(WATER_MAX, app.getWater(b.tile) + 4));
    done ~= id;
  }
  foreach(id; done) app.world.blocks.remove(id);
  app.world.blocksDirty = true;
}