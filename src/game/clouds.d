/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : spawnBlock;
import chunk : faceData;
import gameobjects : Clouds;
import noise : smoothNoise;
import serialization : readData, writeData;
import tile : FACE_OFFSETS, getWater, setWater, getTileAt;
import water : WATER_MAX;

enum int CLOUD_LAYERS = 8;              // Layers
enum int CLOUD_STEP = 6;                // Step
enum float CLOUD_THRESHOLD = 0.90f;     // Threshold
enum float CLOUD_FREQ = 0.06f;          // frequency
enum int CLOUD_SPAWN_CHANCE = 4;        // % of ticks that spawn a new cloud seed
enum float CLOUD_SPAWN_AMOUNT = 0.05f;  // density added per seed (>= 1/CLOUD_LAYERS so a layer shows)
enum int RAIN_DROPS_PER_TICK = 500;     // sparse
enum float RAIN_DEPLETE = 0.03f;        // density removed from a cloud cell per drop spawned
enum float CLOUD_DMAX =  1.0f;          // max positive density (thickest cloud)
enum float CLOUD_DMIN =  0.0f;          // max negative density (fully cleared)

private bool isCloud(ref GameApp app, int gx, int y, int gz) {
  if(y < 0 || y >= CLOUD_LAYERS) return false;
  auto p = [gx, gz] in app.world.cloudDensity;
  if(p is null) return false;
  return y < (*p) * CLOUD_LAYERS;
}

void seedClouds(ref GameApp app, int[3] coord) {
  int cs = app.world.chunkSize;
  int baseX = coord[0] * cs, baseZ = coord[2] * cs;
  for(int lz = 0; lz < cs; lz += CLOUD_STEP)
  for(int lx = 0; lx < cs; lx += CLOUD_STEP) {
    int gx = (baseX + lx) / CLOUD_STEP, gz = (baseZ + lz) / CLOUD_STEP;
    if([gx, gz] in app.world.cloudDensity) continue;        // already seeded
    float n = smoothNoise([gx*CLOUD_FREQ, gz*CLOUD_FREQ], 1337);   // 2D, one sample per column
    float d = (n - CLOUD_THRESHOLD) / 0.2f;
    app.world.cloudDensity[[gx, gz]] = d < 0 ? 0 : (d > 1 ? 1 : d);
  }
}

void spawnClouds(ref GameApp app) {
  if(uniform(0, 100) >= CLOUD_SPAWN_CHANCE) return;     // most ticks: nothing
  auto coords = app.world.chunks.keys;
  if(coords.length == 0) return;
  int cs = app.world.chunkSize;
  int[3] cc = coords[uniform(0, coords.length)];
  int gx = (cc[0]*cs + uniform(0, cs)) / CLOUD_STEP;
  int gz = (cc[2]*cs + uniform(0, cs)) / CLOUD_STEP;
  app.world.cloudDensity[[gx, gz]] += CLOUD_SPAWN_AMOUNT;
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
    for(int lz = 0; lz < cs; lz += CLOUD_STEP) { for(int lx = 0; lx < cs; lx += CLOUD_STEP) {
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
    } }
  }
  app.world.clouds.instances = inst;
  app.world.clouds.instances.buffered = false;
}

/** Relax cloud density toward 0 and clamp; prune negligible entries. */
void decayCloudDensity(ref GameApp app) {
  int[2][] dead;
  foreach(key, ref d; app.world.cloudDensity) {
    if(d > CLOUD_DMAX){ d = CLOUD_DMAX; }
    if(d < CLOUD_DMIN){ d = CLOUD_DMIN; }
    if(d == 0){ dead ~= key; }            // back to baseline -> drop from map
  }
  foreach(k; dead) app.world.cloudDensity.remove(k);
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

/** Persisted cloud density cell. */
struct CloudDiff { int gx, gz; float density; }

/** Save mutable cloud density deltas. */
void saveClouds(ref GameApp app) {
  CloudDiff[] flat;
  foreach(key, d; app.world.cloudDensity) if(d != 0) flat ~= CloudDiff(key[0], key[1], d);
  if(flat.length == 0) { SDL_RemovePath(app.world.cloudsPath()); return; }
  writeData(app.world.cloudsPath(), flat, cast(uint)flat.length);
}

/** Load cloud density deltas. */
void loadClouds(ref GameApp app) {
  CloudDiff[] flat;
  uint h;
  if(!readData(app.world.cloudsPath(), flat, h)) return;
  app.world.cloudDensity = null;
  foreach(ref c; flat) app.world.cloudDensity[[c.gx, c.gz]] = c.density;
  SDL_Log("loadClouds: %d cells", cast(int)flat.length);
}
