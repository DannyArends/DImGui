/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import animation : animateAsset;
import assimp : OpenAsset;
import block : findFreeFood, noBlock, itemOf;
import bone : mergeBones;
import entity : buildSkeleton, isMoving, poseEntity, entityFor, tickEntity, entityMove;
import feature : interactFeaturesAt, findNearestFoodFeature;
import gameobjects : Animals;
import geometry : Geometry;
import jobs : Job, consumeCarried;
import lattice : tileToWorld, tileCoord, worldCoord, chunkCoord;
import material : registerMaterials;
import matrix : translateScale, scale, position, rotate;
import noise : noiseHTT;
import resources : foodValue;
import scheduler : roam, dispatchJob, progressJob;
import sfx : play;
import textures : mapTextures;
import tile : getWater, setWater;
import vector : manhattan;
import water : findNearestWater;
import world : nextEntityUID;

enum animalStep = 4.0f;    // base step rate (moveT/sec, divided by tile cost)
enum animalHop  = 0.9f;    // hop arc height
enum float NEED_SEEK = 0.55f;    // start foraging when a need crosses this

/** Runtime animal: shared pawn (4 inventory slots) + species type. */
struct Animal {
  Entity!4 entity;                              /// Shared pawn state
  alias entity this;
  uint type = 0;                                /// Index into entityTable

  Job!Animal[] jobStack;                        /// Personal jobs (graze / drink)
  @property bool hasJob() const { return jobStack.length > 0; }
  @nogc void clearGoal() nothrow { jobStack = []; targetTile = noTile; repathAttempts = 0; state = EntityState.Idle; }
  @property ref Job!Animal currentJob() { return jobStack[0]; }

  bool tickNeeds(ref GameApp app) { return app.tryAnimalNeeds(this); }
  void whenIdle(ref GameApp app) {
    if(++idleTicks[0] > idleTicks[1]) { idleTicks[0] = 0; idleTicks[1] = uniform(4, 24); app.roam(this); if(path.length) state = EntityState.Wandering; }
  }
  void onWork(ref GameApp app) {}                                       // animals carry nothing
  void onReject(ref GameApp app, ref Job!Animal job) { clearGoal(); }
  void onBlocked(ref GameApp app) { state = EntityState.Idle; }
  void onSubJobComplete(ref GameApp app) { if(jobStack.length) jobStack = jobStack[1..$]; if(!hasJob) state = EntityState.Idle; }
  void onStuck(ref GameApp app) {}
  void onPathResult(ref GameApp app, PathResult r) {
    if(app.world.animals !is null) { foreach(ref x; app.world.animals.animals) if(x.uid == r.uid) {
      x.path = r.success ? r.path : null;
      x.state = r.success ? (x.hasJob ? EntityState.Moving : EntityState.Wandering) : EntityState.Idle;
      return;
    } }
  }
}

/** A spawn decision produced off-thread: which animal type at which tile. */
struct AnimalSpawn { int[3] tile; uint type; }

/** Per-frame: advance each animal's step and refresh its instance transform. */
void animalFrame(ref GameApp app, Animals herd, float dt) {
  foreach(ref a; herd.animals) {
    if(a.isFalling || !a.state.isMoving) continue;
    app.entityMove(a, dt, animalStep, animalHop);
  }
  foreach(mesh; herd.meshes) mesh.instances.reset();
  foreach(ref a; herd.animals) {
    if(app.world.chunkCoord(a.tile) !in app.world.chunks) continue;
    app.poseEntity(herd, a, entityTable[a.type], dt);
  }
  foreach(mesh; herd.meshes) mesh.syncInstances();
  herd.syncInstances();
}

/** Graze: walk to a free food block or berry bush; eat / harvest on arrival. */
Job!Animal grazeJob(int[3] target) {
  return Job!Animal("Grazing", target, Substance.None, [], true, reach: Reach.Adjacent,
    onArrive: (ref GameApp app, ref Animal a) {
      app.progressJob(a, 0.5f, () {
        uint food = findFreeFood(app.world, a.tile, false);        // loose food, not stockpiles
        if(food != noBlock && manhattan(app.world.drops[food].tile, a.tile) <= 1) {
          float restore = foodValue(app.world.drops.itemOf(food));
          app.consumeCarried(a, food);
          a.hunger = a.hunger > restore ? a.hunger - restore : 0.0f;
          app.play("DM-CGS-16", 0.4f);
          app.world.drops.dirty = true;
        } else {
          app.interactFeaturesAt(a.currentJob.targetTile);         // harvest the bush we walked to
        }
      });
    },
    onFail: (ref GameApp app, ref Animal a) { a.jobStack = []; a.state = EntityState.Idle; });
}

/** Drink: walk to water's edge; reset thirst on arrival (no cup). */
Job!Animal animalDrinkJob(int[3] waterCell) {
  return Job!Animal("Drinking", waterCell, Substance.None, [], true, reach: Reach.Adjacent,
    onArrive: (ref GameApp app, ref Animal a) {
      app.progressJob(a, 0.5f, () {
        int[3] w = a.currentJob.targetTile;
        if(app.world.getWater(w) > 0) app.world.setWater(w, cast(ubyte)(app.world.getWater(w) - 1));
        a.thirst = 0.0f;
        app.play("DM-CGS-08", 0.4f);
        app.world.drops.dirty = true;
      });
    },
    onFail: (ref GameApp app, ref Animal a) { a.jobStack = []; a.state = EntityState.Idle; });
}

/** Dispatch a graze or drink job if hungry/thirsty. */
bool tryAnimalNeeds(ref GameApp app, ref Animal a) {
  if(a.needs[Need.Thirst] >= NEED_SEEK) {
    int[3] standAt;
    int[3] cell = app.world.findNearestWater(a.tile, standAt);
    if(cell != noTile) { app.dispatchJob(a, animalDrinkJob(cell)); return true; }
  }
  if(a.needs[Need.Hunger] >= NEED_SEEK) {
    uint food = findFreeFood(app.world, a.tile, false);
    int[3] foodTile = (food != noBlock) ? app.world.drops[food].tile : noTile;
    int[3] bushTile = app.findNearestFoodFeature(a.tile);

    int[3] target = noTile;
    if(foodTile != noTile && bushTile != noTile){
      target = (manhattan(foodTile, a.tile) <= manhattan(bushTile, a.tile)) ? foodTile : bushTile;
    }else if(foodTile != noTile){ target = foodTile;
    }else if(bushTile != noTile){ target = bushTile; }

    if(target != noTile) { app.dispatchJob(a, grazeJob(target)); return true; }
  }
  return false;
}

/** Per-tick: bootstrap the next step, or (when idle) pathfind a new wander target. */
void animalTick(ref GameApp app, Animals herd) {
  foreach(ref a; herd.animals) app.tickEntity(a);
}

Animals ensureAnimals(ref GameApp app) {
  if(app.world.animals !is null) return app.world.animals;
  auto herd = new Animals();
  herd.onFrame = (float dt){ animalFrame(app, herd, dt); };
  herd.onTick  = (){ animalTick(app, herd); };
  app.world.animals = herd;
  app.objects ~= herd;
  foreach(ref e; entityTable) foreach(ref br; e.brushes) {   // register every animal brush mesh once
    if(e.spawnOn.length == 0 || br.mesh in herd.meshes) continue;
    auto mesh = makePrimitive(br.mesh);
    if(mesh is null) continue;
    mesh.initInstanced("Animal:" ~ br.mesh);
    mesh.animations.length = 1;   // select the ANIMATED pipeline; boneCount stays 0 so updateMeshInfo leaves meshdef[3] alone
    mesh.movable = true;
    herd.meshes[br.mesh] = mesh;
    app.objects ~= mesh;
  }
  return herd;
}

/** Place an animal in the world and append its instance row. */
void addAnimal(ref GameApp app, ref Animal a) {
  auto herd = app.ensureAnimals();
  auto wp = app.world.tileToWorld(a.tile);
  a.visualPos = [wp[0], wp[1], wp[2]];
  a.moveFrom = a.moveTo = a.visualPos; a.moveT = 1.0f;
  app.buildSkeleton(herd, a.uid, entityTable[a.type]);
  herd ~= a;
}

/** the spawn record + worker-side decision */
void seedChunkAnimalSpawns(ref ChunkData data, immutable(WorldData) wd) {
  const int chunkSize = wd.chunkSize;
  const int surfaceLimit = wd.tileCount - chunkSize;

  for(int i = 0; i < wd.tileCount; i++) {
    const auto tt = data.tileTypes[i];
    if(tt == ResourceType.None) continue;
    if(i < surfaceLimit && data.tileTypes[i + chunkSize] != ResourceType.None) continue;

    const auto ttIdx = cast(size_t)tt;
    if(ttIdx >= RESOURCE_COUNT || spawnLookup[ttIdx].count == 0) continue;

    const auto wc = wd.worldCoord(data.coord, wd.tileCoord(i));
    const auto n = noiseHTT(wc[0], wc[2], wd.seed);
    const group = spawnLookup[ttIdx];
    for(ubyte g = 0; g < group.count; g++) {
      const size_t aType = group.animalIndices[g];
      ref const at = entityTable[aType];
      if(n[2] < at.noiseThreshold || at.hashMod != 0 && ((wc[0] * at.hashSeed1) ^ (wc[2] * at.hashSeed2)) % at.hashMod != at.hashRem) continue;
      data.animalSpawns ~= AnimalSpawn([wc[0], wc[1] + 1, wc[2]], cast(uint)aType);
    }
  }
}

/** Main-thread: Insert the precomputed spawns */
void seedChunkAnimals(ref GameApp app, ref ChunkData data) {
  foreach(ref s; data.animalSpawns) {
    Animal a = {Entity!4(EntityData!4(nextEntityUID++, Colors.white, s.tile)), s.type };
    a.idleTicks[1] = uniform(4, 24);
    app.addAnimal(a);
  }
  if(data.animalSpawns.length && app.world.animals !is null) app.world.animals.syncInstances();
}

/** Despawn animals currently inside an evicted chunk (mirrors removeAllFeatures). */
void removeChunkAnimals(ref GameApp app, int[3] coord) {
  auto herd = app.world.animals;
  if(herd is null) return;
  bool any = false;
  size_t i = 0;
  app.freeSkeleton(herd, herd.animals[i].uid);
  while(i < herd.animals.length) {
    if(app.world.chunkCoord(herd.animals[i].tile) == coord) { herd.remove(i); any = true; }  // swap-remove
    else i++;
  }
  if(any) herd.syncInstances();
}

