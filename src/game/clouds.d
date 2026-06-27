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
import vector : x, z;
import water : WATER_MAX, WATER_TARGET_ACTIVE, activeSim;

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

/** World tile X/Z -> cloud-cell key (coarse CLOUD_STEP grid). */
@nogc pure int[2] cloudCell(int tx, int tz) nothrow { return [tx / CLOUD_STEP, tz / CLOUD_STEP]; }

/** Cloud-cell key -> a random world tile X/Z inside that cell. */
int[2] cloudTile(const int[2] key) { return [key[0]*CLOUD_STEP + uniform(0, CLOUD_STEP), key[1]*CLOUD_STEP + uniform(0, CLOUD_STEP)]; }

/** Seed cloud density for every cloud-cell column over a newly-loaded chunk from 2D noise; skips already-seeded cells. */
void seedClouds(ref World world, const int[3] coord) {
  int cs = world.chunkSize;
  int baseX = coord.x * cs, baseZ = coord.z * cs;
  for(int lz = 0; lz < cs; lz += CLOUD_STEP) {
  for(int lx = 0; lx < cs; lx += CLOUD_STEP) {
    auto cell = cloudCell(baseX + lx, baseZ + lz);
    if(cell in world.cloudDensity) continue;
    float d = (smoothNoise([cell[0]*CLOUD_FREQ, cell[1]*CLOUD_FREQ], 1337) - CLOUD_THRESHOLD) / 0.2f;
    world.cloudDensity[[cell[0], cell[1]]] = d < 0 ? 0 : (d > 1 ? 1 : d);
  } }
}

/** Occasionally (CLOUD_SPAWN_CHANCE) add a moisture pulse to one random cloud-cell over a random loaded chunk. */
void spawnClouds(ref World world) {
  if(uniform(0, 10000) >= CLOUD_SPAWN_CHANCE) return;     // most ticks: nothing
  auto coords = world.chunks.keys;
  auto cs = world.chunkSize;
  if(coords.length == 0) return;
  int[3] cc = coords[uniform(0, coords.length)];
  world.cloudDensity[cloudCell(cc[0] * cs + uniform(0, cs), cc[2] * cs + uniform(0, cs))] += CLOUD_SPAWN_AMOUNT;
}

/** Build the cloud face-instance mesh from a density snapshot over the given chunk coords (pure; runs on a worker). */
DrawInstance[] buildCloudInstances(const WorldData wd, const float[int[2]] density, const int[3][] coords) {
  float h(int gx, int gz){ auto p = [gx,gz] in density; return((p is null)? 0.0f : (*p) * CLOUD_LAYERS); }
  float baseY = wd.height + 8.0f * wd.tileHeight; 
  float voxH = wd.tileHeight*CLOUD_STEP;
  float vox = CLOUD_STEP*wd.tileSize;

  DrawInstance[] inst;
  foreach(coord; coords) {
    int baseX = coord[0]*wd.chunkSize;
    int baseZ = coord[2]*wd.chunkSize;
    for(int lz=0; lz<wd.chunkSize; lz+=CLOUD_STEP) { for(int lx=0; lx<wd.chunkSize; lx+=CLOUD_STEP) {
      auto cell = cloudCell(baseX + lx, baseZ + lz);
      float hC = h(cell[0], cell[1]); if(hC <= 0) continue;
      float[6] hN = [h(cell[0]+1,cell[1]), h(cell[0]-1,cell[1]), hC, hC, h(cell[0],cell[1]+1), h(cell[0],cell[1]-1)];
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
  return(inst);
}

/** Update cloud density by spawning some new ones and clamp; prune negligible entries. */
void updateCloudDensity(ref World world) {
  world.spawnClouds(); // Add some random moisture
  int active = world.chunks.activeSim();

  int[2][] dead;
  foreach(key, ref d; world.cloudDensity) {
    d -= clamp(0.005f + 0.01f * ((active - WATER_TARGET_ACTIVE) / cast(float)WATER_TARGET_ACTIVE), 0.0f, 0.03f); // relax toward baseline
    if(d > CLOUD_DMAX) d = CLOUD_DMAX;
    if(d <= CLOUD_DMIN) { d = 0; dead ~= key; }   // faded out -> prune
  }
  foreach(k; dead) world.cloudDensity.remove(k);
}

/** Update density of clouds and then make it rain. */
void rainTick(ref GameApp app) {
  int cloudY = app.world.chunkHeight - 1;
  int drops = 0;
  app.world.updateCloudDensity(); // relax + clamp cloud density
  foreach(key, d; app.world.cloudDensity) {
    if(drops >= RAIN_DROPS_PER_TICK) break; // hit the cap -> stop raining
    if(d <= 0 || uniform(CLOUD_DMIN, CLOUD_DMAX) >= d) continue; // skip: Density < 0 or rain chance lucked out
    auto t = cloudTile(key);
    int[3] spawn = [t[0], cloudY, t[1]];
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
    app.setWater(b.tile, cast(ubyte)min(WATER_MAX, app.world.getWater(b.tile) + 4));
    done ~= id;
  }
  foreach(id; done) app.world.blocks.remove(id);
  app.world.blocksDirty = true;
}

/** Persisted cloud density cell. */
struct CloudDiff { int gx, gz; float density; }

/** Save mutable cloud density deltas. */
void saveClouds(const World world) {
  CloudDiff[] flat;
  foreach(key, d; world.cloudDensity) if(d != 0) flat ~= CloudDiff(key[0], key[1], d);
  if(flat.length == 0) { SDL_RemovePath(world.cloudsPath()); return; }
  writeData(world.cloudsPath(), flat, cast(uint)flat.length);
  SDL_Log("saveClouds: %d cells", cast(int)flat.length);
}

/** Load cloud density deltas. */
void loadClouds(ref World world) {
  CloudDiff[] flat;
  uint h;
  if(!readData(world.cloudsPath(), flat, h)) return;
  world.cloudDensity = null;
  foreach(ref c; flat) world.cloudDensity[[c.gx, c.gz]] = c.density;
  SDL_Log("loadClouds: %d cells", cast(int)flat.length);
}

void applyCloudInstances(ref World world, DrawInstance[] inst) {
  world.cloudRebuildPending = false;
  if(world.clouds is null) return;
  world.clouds.instances = inst;
  world.clouds.instances.invalidate();
  if(world.clouds.box !is null) world.clouds.box.dirty = true;
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
  } // no free worker this tick: retry next tick (pending stays false)
}