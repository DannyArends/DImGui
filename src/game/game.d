/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import engine;

public import animal : AnimalT, Animal;
public import block : Block, Drops;
public import clouds : Weather, CloudRequest, CloudResult, CloudDiff;
public import chunk : ChunkData, ChunkField;
public import dwarf : Dwarf;
public import entity : Entity, EntityData, EntityState;
public import feature : FeatureT, FeaturePartT, LSystemBrushT, FeatureDropT, Feature;
public import inventory : Inventory, InventorySlot;
public import jobs : Job, Need, JobState, Reach;
public import gameobjects : Animals, Chunk, Clouds, Dwarves, PathMarkers, GhostCube, WaterTiles;
public import orders : Order;
public import pathfinding : PathRequest, PathResult, PathMarker;
public import fall : Fall;
public import reactions : Reaction, Product, Ingredient, WorkshopUse;
public import searchnode : PathNode;
public import stockpile : Stockpile, StockpileField;
public import tool : ToolMode, PaintState;
public import raws : reactionTable, ResourceType, ResourceClass, ItemTemplate, templateData, resourceData, heightToResource, features, animalTable;
public import resources : ClassVal, ResourceT, ItemTemplateT, Item, traversable, buildable, cost, maxStack, isFood, foodValue;
public import vegetation : Vegetation;
public import world : World, WorldData;

import animalwindow : showAnimalContent;
import block : settleBlocks;
import buildwindow : showBuildContent;
import clouds : buildCloudInstances, applyCloudInstances;
import chunk : buildChunkData, finalizeChunk;
import dwarf : spawnDwarf, loadDwarfs, settleDwarves;
import dwarfwindow : showDwarfContent;
import fpswindow : showFPSContent;
import imgui : iconTextStr;
import icosahedron : refineIcosahedron;
import inventorywindow : showInventoryContent;
import lights : updateSun;
import lightswindow : showLightsContent;
import matrix;
import normals : computeTangents;
import pathfinding : canMoveTo, dispatchPathResult, pathfindWorker, dispatchPendingPaths;
import resources : injectResourceMeshes, updateMaterials;
import settingswindow : showSettingsContent;
import stockpilewindow : showStockpileContent;
import text : addWorldText;
import threading : TaskThread, drainMessages;
import toolbar : showToolbar;
import world : loadWorld, saveWorld, updateWorld;
import waterwindow : showWaterContent;
import worldwindow : showWorldContent;
import wboit: testWBOIT;

/** Worker thread variant that also handles chunk building and pathfinding requests */
class GameTaskThread : TaskThread {
  /** Construct a game worker bound to the main thread's Tid */
  this(Tid id, bool verbose = false) { super(id, verbose); }

  /** Per-loop: build a chunk or run a pathfinding search on request, sending the result back */
  override void handleGameObjects() {
    receiveTimeout(dur!"msecs"(-1),
      (immutable(WorldData) wd, int[3] coord) {
        auto data = buildChunkData(wd, coord);
        main.send(cast(immutable(ChunkData))data, mytid);
      },
      (immutable(WorldData) wd, PathRequest req) {
        auto result = pathfindWorker(wd, req);
        main.send(cast(immutable(PathResult))result, mytid);
      },
      (immutable(WorldData) wd, immutable(CloudRequest) req) {
        float[int[2]] density;
        foreach(c; req.cells) density[c.key] = c.density;
        auto inst = buildCloudInstances(wd, density, req.coords);
        main.send(cast(immutable(CloudResult))CloudResult(inst), mytid);
      }
    );
  }
}

/** Top-level Game state: engine App plus the game World
  TODO:
    - Workshops, and crafting at workshops
    - Liquid barrels for wine/drinks from berries
    - Barrels and Bins for stockpiles
    - Allow stockpiles to be extended / shrunk / redrawn
    - Render crafted objects through assimp models 
    - Per-dwarf labor roles / job filtering (+ Stockpile priorities / hauling logistics)
    - Dwarf skills & experience
    - Item quality tiers
    - Farming / planting
    - Furniture placement (beds, tables) as world objects
    - Wildlife & combat
    */
struct GameApp {
  App app;
  alias app this;

  World world;
  Persist[] persistables;
  bool regenerate = false;
  bool paused = false;
  float timeScale = 1.0f;
}

/** Set up worker factory and camera, load the world, build game UI windows, and spawn or load dwarves */
void initGame(ref GameApp app) {
  app.concurrency.factory = (Tid tid, bool verbose) => new GameTaskThread(tid, verbose);
  app.camera.canMoveTo = (float[3] pos){ return app.world.canMoveTo(pos); };
  SDL_Log("initGame: loadWorld");
  app.loadWorld();
  SDL_Log("initGame: updateSun");
  app.updateSun();
  SDL_Log("initGame: gameWindows");
  app.gameWindows ~= GameWindow("##toolbar", (uint font){ app.showToolbar(font); }, true, false, true);
  app.gameWindows ~= GameWindow("##buildselect", (uint font){ app.showBuildContent(font); }, true, false, true);
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_INBOX, "Inventory"), (uint font){ app.showInventoryContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_WAREHOUSE, "Stockpiles"), (uint font){ app.showStockpileContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GLOBE, "World"), (uint font){ app.showWorldContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_USER, "Dwarfs"), (uint font){ app.showDwarfContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_PAW, "Animals"), (uint font){ app.showAnimalContent(font); });
  app.gameWindows ~= GameWindow("FPS", (uint font){ app.showFPSContent(font); }, true, false, true);
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_LIGHTBULB, "Lights"), (uint font){ app.showLightsContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GEAR, "Settings"), (uint font){ app.showSettingsContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_WATER, "Water"), (uint font){ app.showWaterContent(font); });

  SDL_Log("createScene: Add Text");
  app.addWorldText("CalderaD", [12.0f, 10.0f, 0.0f], [90.0f, 0.0f, 0.0f]);
  SDL_Log("createScene: WBOIT test rectangles");
  app.testWBOIT();
  SDL_Log("initGame: done");

  app.mainDeletionQueue.add((){ app.saveWorld(); });
}

Geometry makePrimitive(string name) {
  Geometry m;
  switch(name) {
    case "Cube", "Blocks": m = new Cube(); break;
    case "Cylinder": m = new Cylinder(0.4f, 1.0f, 12); break;
    case "Cone": m = new Cone(0.5f, 1.0f, 12); break;
    case "Icosahedron": m = new Icosahedron(); m.computeTangents(); break;
    case "Berries": m = new Icosahedron(); m.computeTangents(); m.refineIcosahedron(3); break;
    default: return null;
  }
  return m;
}

/** Per-frame game update: refresh resource meshes/materials, settle blocks, and stream the world around the camera */
void updateGame(ref GameApp app, double dt) {
  app.injectResourceMeshes();
  if(app.textures.loaded) { 
    app.updateMaterials(); app.textures.loaded = false; 
  }
  app.world.settleBlocks(dt);
  app.settleDwarves(dt);
  app.updateWorld(app.camera.lookat);
  app.shadows.bounds = [app.world.height, app.world.radius];
}

/** Per-frame: dispatch queued paths and drain completed chunk-build and pathfinding results from workers */
void checkGameAsync(ref GameApp app) {
  app.dispatchPendingPaths();
  if(app.drainMessages!ChunkData((d) { app.finalizeChunk(d); }, 2)) app.camera.isDirty = true;
  app.drainMessages!PathResult((r) { app.dispatchPathResult(r); });
  app.drainMessages!CloudResult((r) { app.world.applyCloudInstances(r.instances); });
}

/** Persist the world to disk on shutdown */
void cleanupGame(ref GameApp app) { app.saveWorld(); }
