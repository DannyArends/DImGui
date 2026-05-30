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
import lights : updateSun;
import lightswindow : showLightsContent;
import pathfinding : canMoveTo, pathfindWorker, dispatchPendingPaths;
import resources : injectResourceMeshes, updateMaterials;
import settingswindow : showSettingsContent;
import threading : TaskThread;
import world : loadWorld, saveWorld, updateWorld;
import worldwindow : showWorldContent;

class GameTaskThread : TaskThread {
  this(Tid id, bool verbose = false) { super(id, verbose); }

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

struct GameApp {
  App app;
  alias app this;

  World world;
  bool showPaths = false;
  bool showRays = false;
  bool paused = false;
}

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
  SDL_Log("initGame: done");
}

void updateGame(ref GameApp app) {
  float dt = (app.time[FRAMESTOP] - app.time[LASTFRAME]) / 100.0f;
  app.injectResourceMeshes();
  if(app.textures.loaded) { app.updateMaterials(); app.textures.loaded = false; }
  app.world.settleBlocks(dt);
  app.updateWorld(app.camera.lookat);
  app.shadows.bounds = [app.world.height, app.world.radius];
}

void checkGameAsync(ref GameApp app) {
  app.dispatchPendingPaths();
  receiveTimeout(dur!"msecs"(-1), (immutable(ChunkData) data, Tid tid) {
    app.concurrency.workers[tid] = false;
    app.finalizeChunk(cast(ChunkData)data);
  });
  receiveTimeout(dur!"msecs"(-1), (immutable(PathResult) result, Tid tid) {
    app.concurrency.workers[tid] = false;
    app.applyPathResult(cast(PathResult)result);
  });
}

void cleanupGame(ref GameApp app) { app.saveWorld(); }
