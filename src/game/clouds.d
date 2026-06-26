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
import water : WATER_MAX, WATER_TARGET_ACTIVE;

enum int CLOUD_LAYERS = 8;              // Layers
enum int CLOUD_STEP = 6;                // Step
enum float CLOUD_THRESHOLD = 0.85f;     // Threshold
enum float CLOUD_FREQ = 0.06f;          // frequency
enum int CLOUD_SPAWN_CHANCE = 5;        // %% of ticks that spawn a new cloud seed
enum float CLOUD_SPAWN_AMOUNT = 0.01f;  // density added per seed (>= 1/CLOUD_LAYERS so a layer shows)
enum int RAIN_DROPS_PER_TICK = 500;     // sparse
enum float RAIN_DEPLETE = 0.05f;        // density removed from a cloud cell per drop spawned
enum float CLOUD_DMAX =  1.0f;          // max positive density (thickest cloud)
enum float CLOUD_DMIN =  0.0f;          // max negative density (fully cleared)

/** Cloud column height in layers for grid column (gx,gz); 0 if no cloud there. */
private float cloudHeight(ref GameApp app, int gx, int gz) {
  auto p = [gx, gz] in app.world.cloudDensity;
  return p is null ? 0.0f : (*p) * CLOUD_LAYERS;
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
  if(uniform(0, 10000) >= CLOUD_SPAWN_CHANCE) return;     // most ticks: nothing
  auto coords = app.world.chunks.keys;
  if(coords.length == 0) return;
  int cs = app.world.chunkSize;
  int[3] cc = coords[uniform(0, coords.length)];
  int gx = (cc[0]*cs + uniform(0, cs)) / CLOUD_STEP;
  int gz = (cc[2]*cs + uniform(0, cs)) / CLOUD_STEP;
  app.world.cloudDensity[[gx, gz]] += CLOUD_SPAWN_AMOUNT;
}

DrawInstance[] buildCloudInstances(const WorldData wd, const float[int[2]] density, const int[3][] coords) {
  float h(int gx, int gz){ auto p = [gx,gz] in density; return p is null ? 0.0f : (*p)*CLOUD_LAYERS; }
  float baseY = wd.height + 8.0f * wd.tileHeight; 
  float voxH = wd.tileHeight*CLOUD_STEP;
  float vox = CLOUD_STEP*wd.tileSize;

  DrawInstance[] inst;
  foreach(coord; coords) {
    int baseX = coord[0]*wd.chunkSize;
    int baseZ = coord[2]*wd.chunkSize;
    for(int lz=0; lz<wd.chunkSize; lz+=CLOUD_STEP) { for(int lx=0; lx<wd.chunkSize; lx+=CLOUD_STEP) {
      int gx = (baseX+lx)/CLOUD_STEP;
      int gz = (baseZ+lz)/CLOUD_STEP;
      float hC = h(gx,gz); if(hC<=0) continue;
      float[6] hN=[h(gx+1,gz),h(gx-1,gz),hC,hC,h(gx,gz+1),h(gx,gz-1)];
      foreach(y; 0..CLOUD_LAYERS) { 
        if(y>=hC) continue;
        float px=(baseX+lx)*wd.tileSize, py=baseY+y*voxH, pz=(baseZ+lz)*wd.tileSize;
        foreach(f; 0..6) {
          int ny = y + FACE_OFFSETS[f][1];
          if(ny >= 0 && ny < CLOUD_LAYERS && ny < hN[f]) continue;
          inst ~= DrawInstance(cast(uint)ResourceType.Ice01, faceData(f, px , py, pz, vox, voxH));
        }
      }
    } }
  }
  return inst;
}

/** Relax cloud density toward 0 and clamp; prune negligible entries. */
void decayCloudDensity(ref GameApp app) {
  int[2][] dead;
  foreach(key, ref d; app.world.cloudDensity) {
    d -= app.world.cloudDecay;                 // relax toward baseline
    if(d > CLOUD_DMAX) d = CLOUD_DMAX;
    if(d <= CLOUD_DMIN) { d = 0; dead ~= key; }   // faded out -> prune
  }
  foreach(k; dead) app.world.cloudDensity.remove(k);

  int active = 0;
  foreach(coord; app.world.chunks.keys) active += cast(int)app.world.chunks[coord].active.length;
  float err = (active - WATER_TARGET_ACTIVE) / cast(float)WATER_TARGET_ACTIVE;
  app.world.cloudDecay = clamp(app.world.cloudDecay * (1.0f + 0.1f * err), 0.0001f, 0.5f);
}

void rainTick(ref GameApp app) {
  int cs = app.world.chunkSize;
  int cloudY = app.world.chunkHeight - 1;
  int drops = 0;

  foreach(key, d; app.world.cloudDensity) {
    if(drops >= RAIN_DROPS_PER_TICK) break;        // hit the cap -> stop raining
    if(d <= 0) continue;
    if(uniform(0.0f, 1.0f) >= d) continue;          // rain chance scales with density
    int tx = key[0]*CLOUD_STEP + uniform(0, CLOUD_STEP);
    int tz = key[1]*CLOUD_STEP + uniform(0, CLOUD_STEP);
    int[3] spawn = [tx, cloudY, tz];
    if(app.world.getTileAt(spawn) != ResourceType.None) continue;
    uint id = app.spawnBlock(spawn, ResourceType.Water);
    if(auto b = id in app.world.blocks) { b.fall.weight = 20.0f; b.fall.start(app.world, spawn, -app.world.blockOffset); }
    app.world.cloudDensity[key] -= RAIN_DEPLETE;
    drops++;
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

void applyCloudInstances(ref GameApp app, DrawInstance[] inst) {
  app.world.cloudRebuildPending = false;
  if(app.world.clouds is null) return;
  app.world.clouds.instances = inst;
  app.world.clouds.instances.invalidate();
  if(app.world.clouds.box !is null) app.world.clouds.box.dirty = true;
}

/** Cloud re-mesh worker message: a flattened density snapshot + the loaded chunk coords. */
struct CloudCell { int[2] key; float density; }
struct CloudRequest { immutable(CloudCell)[] cells; immutable(int[3])[] coords; }
struct CloudResult { DrawInstance[] instances; }

/** Build the worker payload from current density and dispatch to a free worker (one in flight at a time). */
void requestCloudRebuild(ref GameApp app) {
  if(app.world.clouds is null || app.world.cloudRebuildPending) return;
  CloudCell[] cells;
  foreach(k, v; app.world.cloudDensity){ cells ~= CloudCell([k[0], k[1]], v); }
  auto coords = app.world.chunks.keys;
  foreach(tid; app.concurrency.workers.keys) {
    if(!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      app.world.cloudRebuildPending = true;
      tid.send(cast(immutable(WorldData))app.world.data, immutable(CloudRequest)(cells.idup, coords.idup));
      return;
    }
  }
  // no free worker this tick: retry next tick (pending stays false)
}