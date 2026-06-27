/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import engine;

public import block : Block;
public import clouds : CloudRequest, CloudResult;
public import chunk : ChunkData;
public import dwarf : Dwarf, DwarfData, DwarfState;
public import feature : FeatureT, FeaturePartT, LSystemPartT, LSystemBrushT, FeatureDropT, Feature;
public import inventory : Inventory;
public import jobs : Job, JobState, Reach;
public import gameobjects : Chunk, Clouds, Dwarves, PathMarkers, GhostCube, WaterTiles;
public import pathfinding : PathRequest, PathResult;
public import physx : Fall;
public import searchnode : PathNode;
public import stockpile : Stockpile;
public import tool : ToolMode, PaintState;
public import tile : builtTile, noTile, storedTile, TileDiff;
public import raws : ResourceType, resourceData, heightToResource, features;
public import resources : ResourceT;
public import world : World, WorldData;

import block : settleBlocks;
import buildwindow : showBuildContent;
import clouds : buildCloudInstances, applyCloudInstances;
import chunk : buildChunkData, finalizeChunk;
import dwarf : spawnDwarf, loadDwarfs, settleDwarves;
import dwarfwindow : showDwarfContent;
import fpswindow : showFPSContent;
import imgui : iconTextStr;
import inventorywindow : showInventoryContent;
import jobs : applyPathResult;
import lights : updateSun;
import lightswindow : showLightsContent;
import normals : computeTangents;
import pathfinding : canMoveTo, pathfindWorker, dispatchPendingPaths;
import resources : injectResourceMeshes, updateMaterials;
import settingswindow : showSettingsContent;
import stockpilewindow : showStockpileContent;
import threading : TaskThread, drainMessages;
import toolbar : showToolbar;
import turtle : interpret;
import world : loadWorld, saveWorld, updateWorld;
import waterwindow : showWaterContent;
import worldwindow : showWorldContent;

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

/** Top-level application state: engine App plus the game World and debug toggles */
struct GameApp {
  App app;
  alias app this;

  World world;
  bool showPaths = false;
  bool showRays = false;
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
  app.gameWindows ~= GameWindow("FPS", (uint font){ app.showFPSContent(font); }, true, false, true);
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_LIGHTBULB, "Lights"), (uint font){ app.showLightsContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GEAR, "Settings"), (uint font){ app.showSettingsContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_WATER, "Water"), (uint font){ app.showWaterContent(font); });
  SDL_Log("initGame: loadDwarfs");
  if(!app.loadDwarfs()) { for(int x = 0; x <= 7; x++) app.spawnDwarf(); }


  SDL_Log("createScene: Add Text");
  app.objects ~= new Text(app, "CalderaD");
  app.objects[($-1)].rotate([90.0f, 0.0f, 0.0f]);
  app.objects[($-1)].position([6.0f, 4.0f, 0.0f]);
  SDL_Log("initGame: done");

// --- TURTLE TEST (temporary) ---
  SDL_Log("turtle test");
  auto trunk = new Cone(0.5f, 1.0f, 12);  trunk.initInstanced(() => "TurtleTrunk");
  auto leaf  = new Icosahedron();  leaf.computeTangents();  leaf.initInstanced(() => "TurtleLeaf");

  TurtleConfig cfg;
  cfg.angle = 35.0f;
  cfg.brush['C'] = TurtleBrush(-1, 0.18f, 1.0f, true);    // cone segment, advances
  cfg.brush['I'] = TurtleBrush(-1, 0.6f,  0.6f, false);   // leaf blob, no advance

  float[4] q0 = [0.0f, 0.0f, 0.0f, 1.0f];                 // identity
  auto grouped = interpret("CCC[+CCI][-CCI][&CCI][^CCI]CCI", cfg, [10.0f, 2.0f, 0.0f], q0);  // origin in world coords

  if(auto p = 'C' in grouped) trunk.instances.items = *p;
  if(auto p = 'I' in grouped) leaf.instances.items  = *p;
  trunk.instances.invalidate(); leaf.instances.invalidate();
  app.objects ~= trunk;   // no position() call
  app.objects ~= leaf;    // no position() call
  // --- END TURTLE TEST ---
  
  app.mainDeletionQueue.add((){ app.saveWorld(); });
}

/** Per-frame game update: refresh resource meshes/materials, settle blocks, and stream the world around the camera */
void updateGame(ref GameApp app, double dt) {
  app.injectResourceMeshes();
  if(app.textures.loaded) { app.updateMaterials(); app.textures.loaded = false; }
  app.world.settleBlocks(dt);
  app.settleDwarves(dt);
  app.updateWorld(app.camera.lookat);
  app.shadows.bounds = [app.world.height, app.world.radius];
}

/** Per-frame: dispatch queued paths and drain completed chunk-build and pathfinding results from workers */
void checkGameAsync(ref GameApp app) {
  app.dispatchPendingPaths();
  if(app.drainMessages!ChunkData((d) { app.finalizeChunk(d); }, 2)) app.camera.isDirty = true;
  app.drainMessages!PathResult((r) { app.applyPathResult(r); });
  app.drainMessages!CloudResult((r) { app.world.applyCloudInstances(r.instances); });
}

/** Persist the world to disk on shutdown */
void cleanupGame(ref GameApp app) { app.saveWorld(); }
