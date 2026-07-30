/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : findFreeFood;
import color : randomColor;
import dwarf : findFreeSurfaceTile;
import feature : interactFeaturesAt, findNearestFoodFeature;
import gameobjects : Animals;
import jobs : roam;
import lattice : tileToWorld, tileCoord, worldCoord, chunkCoord, worldToTile;
import matrix : translateScale, scale, position;
import noise : noiseHTT;
import pathfinding : followPath, pathfindTo, stepMove, repathTo, RepathResult, findGoalTile;
import tile : getSuccessors, tileAbove;
import water : findNearestWater;
import world : nextEntityUID;

enum animalStep = 4.0f;    // base step rate (moveT/sec, divided by tile cost)
enum animalHop  = 0.9f;    // hop arc height
enum float NEED_SEEK = 0.55f;    // start foraging when a need crosses this

/** Data-driven animal species, parsed from data/raws/animals.txt into animalTable. */
struct AnimalT {
  string name;                                  /// Species name
  string mesh = "Torus";                        /// Instance mesh (primitive for now)
  string[] spawnOn;                             /// Tile resource types this animal spawns on
  float noiseThreshold = 0.92f;                 /// Hash-noise spawn gate (higher = rarer)
  uint hashSeed1, hashSeed2;                    /// Per-species spawn hash seeds
  uint hashMod, hashRem;                        /// Optional hash bucketing (0 = unused)
  float moveSpeed = 2.0f;                       /// Tiles per second
  float hungerDecay = 0.00040f;                 /// Hunger need increase per tick
  float thirstDecay = 0.00060f;                 /// Thirst need increase per tick
  string diet = "Berry";                        /// Resource (class or type) this animal eats
  float scale = 0.5f, scaleVariance = 0.1f;     /// Instance scale + per-spawn variance
}

/** Runtime animal: shared pawn (4 inventory slots) + species type. */
struct Animal {
  Entity!4 entity;                              /// Shared pawn state
  alias entity this;
  uint type = 0;                                /// Index into animalTable

  Job!Animal[] jobStack;                        /// Personal jobs (graze / drink)
  @property bool hasJob() const { return jobStack.length > 0; }
  @property ref Job!Animal currentJob() { return jobStack[0]; }
}

/** Per-frame: advance each animal's step and refresh its instance transform. */
void animalFrame(ref GameApp app, float dt) {
  if(app.world.animals is null) return;
  foreach(i, ref a; app.world.animals.animals) {
    app.stepMove(a, dt, animalStep, animalHop);
    float scl = animalTable[a.type].scale;
    float sc = (app.world.chunkCoord(a.tile) in app.world.chunks) ? scl : 0.0f;   // hide if chunk unloaded
    Matrix m = scale(Matrix.init, [sc, sc, sc]);
    app.world.animals.instances[i] = position(m, a.visualPos);
  }
  app.world.animals.syncInstances();
}

/** Per-tick: bootstrap the next step, or (when idle) pathfind a new wander target. */
void animalTick(ref GameApp app) {
  if(app.world.animals is null) return;
  foreach(ref a; app.world.animals.animals) {
    a.needs[Need.Hunger] = min(1.0f, a.needs[Need.Hunger] + animalTable[a.type].hungerDecay);
    a.needs[Need.Thirst] = min(1.0f, a.needs[Need.Thirst] + animalTable[a.type].thirstDecay);

    if(a.state == EntityState.WaitingForPath) continue;
    if(a.moveT >= 1.0f && a.path.length > 0) { app.followPath(a); continue; }   // bootstrap next step
    if(a.moveT < 1.0f || a.path.length > 0) continue;                            // mid-step

    // idle → roam (shared with dwarves)
    if(++a.idleTicks[0] > a.idleTicks[1]) {
      a.idleTicks[0] = 0;
      a.idleTicks[1] = uniform(60, 240);
      app.roam(a);
      if(a.path.length > 0) a.state = EntityState.Wandering;
    } else {
      a.state = EntityState.Idle;
    }
  }
}

/** Create the Animals container and register it for rendering + ticking. */
void ensureAnimals(ref GameApp app) {
  if(app.world.animals !is null) return;
  app.world.animals = new Animals();
  app.world.animals.onFrame = (float dt){ animalFrame(app, dt); };
  app.world.animals.onTick  = (){ animalTick(app); };
  app.objects ~= app.world.animals;
}

/** Place an animal in the world and append its instance row. */
void addAnimal(ref GameApp app, ref Animal a) {
  auto wp = app.world.tileToWorld(a.tile);
  a.visualPos = [wp[0], wp[1] + 0.5f, wp[2]];
  a.moveFrom = a.moveTo = a.visualPos;
  a.moveT = 1.0f;
  float s = animalTable[a.type].scale;
  app.world.animals.instances ~= DrawInstance(translateScale(a.visualPos, [s, s, s]), -1, a.color);
  app.world.animals ~= a;
}

/** World tiles where `at` should spawn in this chunk: surface tile, matching spawn type, past the noise + hash gates. */
int[3][] animalSpawnTiles(ref const(WorldData) wd, int[3] coord, const ResourceType[] tileTypes, const AnimalT at) {
  int[3][] result;
  ResourceType[] spawnTypes;
  foreach(s; at.spawnOn) spawnTypes ~= s.to!ResourceType;
  for(int i = 0; i < wd.tileCount; i++) {
    if(tileTypes[i] == ResourceType.None) continue;
    if(i + wd.chunkSize < wd.tileCount && tileTypes[i + wd.chunkSize] != ResourceType.None) continue;
    if(!spawnTypes.canFind(tileTypes[i])) continue;
    auto lc = wd.tileCoord(i);
    auto wc = wd.worldCoord(coord, lc);
    auto n = noiseHTT(wc[0], wc[2], wd.seed);
    if(n[2] < at.noiseThreshold) continue;
    uint hash = (wc[0] * at.hashSeed1) ^ (wc[2] * at.hashSeed2);
    if(at.hashMod != 0 && hash % at.hashMod != at.hashRem) continue;
    result ~= [wc[0], wc[1] + 1, wc[2]];
  }
  return result;
}

/** Spawn a chunk's noise-placed animals on first generation. */
void seedChunkAnimals(ref GameApp app, ref ChunkData data) {
  bool any = false;
  foreach(size_t t, ref at; animalTable) {
    foreach(tile; animalSpawnTiles(app.world.data, data.coord, data.tileTypes, at)) {
      app.ensureAnimals();
      Animal a; a.entity.data = EntityData!4(nextEntityUID++, randomColor(), tile); a.type = cast(uint)t;
      app.addAnimal(a);
      any = true;
    }
  }
  if(any) app.world.animals.syncInstances();
}

/** Despawn animals currently inside an evicted chunk (mirrors removeAllFeatures). */
void removeChunkAnimals(ref GameApp app, int[3] coord) {
  if(app.world.animals is null) return;
  bool any = false;
  size_t i = 0;
  while(i < app.world.animals.animals.length) {
    if(app.world.chunkCoord(app.world.animals.animals[i].tile) == coord) {
      app.world.animals.remove(i);      // swap-remove: last moves into i, so don't advance
      any = true;
    } else i++;
  }
  if(any) app.world.animals.syncInstances();
}

