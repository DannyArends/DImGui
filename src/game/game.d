/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import engine;

public import block : Block;
public import chunk : ChunkData;
public import dwarf : Dwarf, DwarfData, DwarfState;
public import feature : FeatureT, FeaturePartT, FeatureDropT, Feature;
public import inventory : Inventory;
public import jobs : Job;
public import gameobjects : Chunk, Dwarves, PathMarkers, GhostCube;
public import pathfinding : PathRequest, PathResult;
public import searchnode : PathNode;
public import tool : ToolMode, PaintState;
public import tile : builtTile, noTile, TileDiff;
public import raws : ResourceType, resourceData, heightToResource, features;
public import resources : ResourceT;
public import world : World, WorldData;

import block : settleBlocks;
import chunk : buildChunkData, finalizeChunk;
import dwarf : spawnDwarf, loadDwarfs;
import dwarfwindow : showDwarfContent;
import fpswindow : showFPSContent;
import imgui : iconTextStr;
import inventorywindow : showInventoryContent;
import jobs : applyPathResult;
import normals : computeNormals, computeTangents;
import lights : updateSun;
import lightswindow : showLightsContent;
import pathfinding : canMoveTo, pathfindWorker, dispatchPendingPaths;
import resources : injectResourceMeshes, updateMaterials;
import settingswindow : showSettingsContent;
import threading : TaskThread, drainMessages;
import world : loadWorld, saveWorld, updateWorld;
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
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_INBOX, "Inventory"), (uint font){ app.showInventoryContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GLOBE, "World"), (uint font){ app.showWorldContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_USER, "Dwarfs"), (uint font){ app.showDwarfContent(font); });
  app.gameWindows ~= GameWindow("FPS", (uint font){ app.showFPSContent(font); }, true, false, true);
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_LIGHTBULB, "Lights"), (uint font){ app.showLightsContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GEAR, "Settings"), (uint font){ app.showSettingsContent(font); });
  SDL_Log("initGame: loadDwarfs");
  if(!app.loadDwarfs()) { for(int x = 0; x <= 7; x++) app.spawnDwarf(); }


  SDL_Log("createScene: Add Text");
  app.objects ~= new Text(app);
  app.objects[($-1)].computeNormals();
  app.objects[($-1)].computeTangents();
  SDL_Log("initGame: done");
}

/** Per-frame game update: refresh resource meshes/materials, settle blocks, and stream the world around the camera */
void updateGame(ref GameApp app) {
  float dt = (app.time[FRAMESTOP] - app.time[LASTFRAME]) / 100.0f;
  app.injectResourceMeshes();
  if(app.textures.loaded) { app.updateMaterials(); app.textures.loaded = false; }
  app.world.settleBlocks(dt);
  app.updateWorld(app.camera.lookat);
  app.shadows.bounds = [app.world.height, app.world.radius];
}

/** Per-frame: dispatch queued paths and drain completed chunk-build and pathfinding results from workers */
void checkGameAsync(ref GameApp app) {
  app.dispatchPendingPaths();
  if(app.drainMessages!ChunkData((d) { app.finalizeChunk(d); })) app.camera.isDirty = true;
  app.drainMessages!PathResult((r) { app.applyPathResult(r); });
}

/** Persist the world to disk on shutdown */
void cleanupGame(ref GameApp app) { app.saveWorld(); }
