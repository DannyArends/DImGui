/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import engine;

// CTFE Structs
public import rawstructs;
public import raws;

// Normal Structs
public import animal : Animal, AnimalSpawn;
public import block : Block, Drops;
public import clouds : Weather, CloudRequest, CloudResult, CloudDiff;
public import chunk : ChunkData, ChunkField;
public import dwarf : Dwarf;
public import entity : Entity, EntityData, EntityState;
public import feature : Feature;
public import inventory : Inventory, InventorySlot;
public import jobs : Job, Need, JobState, Reach;
public import gameobjects : Animals, Chunk, Clouds, Dwarves, PathMarkers, GhostCube, WaterTiles;
public import orders : Order;
public import pathfinding : PathRequest, PathResult, PathMarker;
public import fall : Fall;
public import searchnode : PathNode;
public import skeleton : Skeleton;
public import stockpile : Stockpile, StockpileField;
public import tool : ToolMode, PaintState;
public import resources : Item, traversable, buildable, cost, maxStack, isFood, foodValue;
public import vegetation : Vegetation;
public import world : World, WorldData;

import animalwindow : showAnimalContent;
import block : settleBlocks;
import buildwindow : showBuildContent;
import boundingbox : computeBoundingBox;
import clouds : buildCloudInstances, applyCloudInstances;
import chunk : buildChunkData, finalizeChunk, postFinalizeChunks;
import dwarf : settleDwarves;
import dwarfwindow : showDwarfContent;
import fpswindow : showFPSContent;
import imgui : iconTextStr;
import inventorywindow : showInventoryContent;
import io : dir;
import lights : updateSun;
import lightswindow : showLightsContent;
import normals : computeTangents;
import pathfinding : canMoveTo, dispatchPathResult, pathfindWorker, dispatchPendingPaths;
import persistence : loadWorld, saveWorld;
import resources : injectResourceMeshes, updateMaterials;
import settingswindow : showSettingsContent;
import stockpilewindow : showStockpileContent;
import text : addWorldText;
import timing : timed;
import threading : TaskThread, drainMessages;
import toolbar : showToolbar;
import world : updateWorld;
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
        auto chunk = new Chunk(buildChunkData(wd, coord), wd);
        chunk.tiles.computeBoundingBox();
        chunk.computeBoundingBox();
        main.send(cast(immutable(Chunk))chunk, mytid);
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
  size_t loadTotal = 0;
}

/** Centered 2D progress bar over the loaded fraction of the initial working set; shown until worldReady. */
void showLoadingBar(ref GameApp app) {
  ImVec2 disp = app.gui.io.DisplaySize;
  igSetNextWindowPos(ImVec2(disp.x * 0.5f, disp.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
  igBegin("##loading", null, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_AlwaysAutoResize);
  igText(cstr("Loading world..."));
  igProgressBar(-1.0f * cast(float)(SDL_GetTicks() % 1000) / 1000.0f, ImVec2(400.0f, 24.0f), "");
  igEnd();
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
  app.gameWindows ~= GameWindow("##loading", (uint font){ if(!app.worldReady) app.showLoadingBar(); }, true, false, true);
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

/** Recursively find <name>.fbx under data/objects/ (falls back to a flat path if not found). */
string modelPath(string name) {
  static string[string] cache; // basename(no ext) -> full path, scanned once
  if(cache is null){ foreach(f; dir("data/objects/", "*.fbx", false)) { cache[stripExtension(baseName(f))] = f; } }
  return cache.getOrElse(name, format("data/objects/%s.fbx", name));
}

Geometry makePrimitive(string name) {
  Geometry m;
  switch(name) {
    case "Cube", "Blocks": m = new Cube(); break;
    case "Cylinder": m = new Cylinder(0.4f, 1.0f, 12); break;
    case "Cone": m = new Cone(0.5f, 1.0f, 12); break;
    case "Berries", "Sphere": m = new Sphere(); break;
    case "Capsule": m = new Capsule(0.5f, 1.0f, 16, 6); break;
    case "Torus": m = new Torus(); break;
    case "Icosahedron": m = new Icosahedron(); m.computeTangents(); break;
    default: return new OpenAsset(toStringz(modelPath(name)), false, true);
  }
  return m;
}

/** Per-frame game update: refresh resource meshes/materials, settle blocks, and stream the world around the camera */
void updateGame(ref GameApp app, double dt) {
  app.timed!injectResourceMeshes();
  if(app.textures.loaded) {
    app.timed!updateMaterials(); app.textures.loaded = false;
  }
  app.world.settleBlocks(dt);
  app.timed!settleDwarves(dt);
  app.timed!updateWorld(app.camera.fps ? app.camera.position : app.camera.lookat);
  app.shadows.bounds = [app.world.height, app.world.radius];
  size_t pending = app.textures.pending.length + app.world.chunks.pending.length;
  if(pending > app.loadTotal) app.loadTotal = pending;                       // grow the denominator as async work queues
  if(!app.worldReady && pending == 0 && app.loadTotal > 0) { SDL_Log("!World Ready!"); app.worldReady = true; }
}

/** Per-frame: dispatch queued paths and drain completed chunk-build and pathfinding results from workers */
void checkGameAsync(ref GameApp app) {
  app.dispatchPendingPaths();
  if(app.drainMessages!Chunk((c) { app.timed!finalizeChunk(c); })) { app.postFinalizeChunks(); }
  app.drainMessages!PathResult((r) { app.dispatchPathResult(r); });
  app.drainMessages!CloudResult((r) { app.world.applyCloudInstances(r.instances); });
}

/** Persist the world to disk on shutdown */
void cleanupGame(ref GameApp app) { app.saveWorld(); }
