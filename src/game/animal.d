/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import dwarf : findFreeSurfaceTile;
import color : randomColor;
import gameobjects : Animals;
import lattice : tileToWorld;
import matrix : translateScale;

uint nextAnimalUID = 1;

enum AnimalState : ubyte { Idle, Wander, SeekFood, SeekWater, Eat, Drink }

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

/** Serializable core of an animal (saved between sessions). */
struct AnimalData {
  uint uid = 0;                                 /// Unique ID
  uint type = 0;                                /// Index into animalTable
  int[3] tile = [0, 0, 0];                      /// Current tile
  float[Need.max + 1] needs = 0.0f;             /// Reuse the Need array (acts on Hunger, Thirst)
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// Instance tint

  @nogc @property float hunger() const { return needs[Need.Hunger]; }
  @nogc @property void hunger(float v) { needs[Need.Hunger] = v; }
  @nogc @property float thirst() const { return needs[Need.Thirst]; }
  @nogc @property void thirst(float v) { needs[Need.Thirst] = v; }
}

/** Runtime animal: serializable data plus movement/behaviour state. */
struct Animal {
  AnimalData data;
  alias data this;
  AnimalState state = AnimalState.Idle;
  float[3] visualPos = [0.0f, 0.0f, 0.0f];      /// Interpolated position
  float[3] moveFrom  = [0.0f, 0.0f, 0.0f];
  float[3] moveTo    = [0.0f, 0.0f, 0.0f];
  float moveT = 1.0f;                           /// 1.0 = arrived
}

/** Per-frame stub (movement interpolation lands in step 4). */
void animalFrame(ref GameApp app, float dt) { }
/** Per-tick stub (needs decay + foraging land in steps 4–5). */
void animalTick(ref GameApp app) { }

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

/** Spawn one animal of `type` on a free surface tile. */
void spawnAnimal(ref GameApp app, uint type = 0) {
  if(type >= animalTable.length) return;
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  app.ensureAnimals();
  Animal a; a.data = AnimalData(nextAnimalUID++, type, tile, 0.0f, randomColor());
  app.addAnimal(a);
  app.world.animals.syncInstances();
}

