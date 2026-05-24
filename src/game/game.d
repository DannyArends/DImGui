/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : settleBlocks;
import chunk : finalizeChunk;
import dwarfwindow : showDwarfContent;
import fpswindow : showFPSContent;
import imgui : iconTextStr;
import inventorywindow : showInventoryContent;
import lightswindow : showLightsContent;
import settingswindow : showSettingsContent;
import jobs : applyPathResult;
import pathfinding : canMoveTo, dispatchPendingPaths;
import resources : injectResourceMeshes;
import world : loadWorld, saveWorld, updateWorld;
import worldwindow : showWorldContent;

struct GameApp {
  App app;
  alias app this;  // GameApp usable everywhere App is expected

  World world;

  bool showPaths = false;
  bool showRays = false;
  bool paused = false;
}

void initGame(ref GameApp app) {
  app.loadWorld();
  app.injectResourceMeshes();
  app.camera.canMoveTo = (float[3] pos){ return app.world.canMoveTo(pos); };
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_INBOX, "Inventory"), (uint font){ app.showInventoryContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GLOBE, "World"), (uint font){ app.showWorldContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_USER, "Dwarfs"), (uint font){ app.showDwarfContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GAUGE, "FPS"), (uint font){ app.showFPSContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_LIGHTBULB, "Lights"), (uint font){ app.showLightsContent(font); });
  app.gameWindows ~= GameWindow(iconTextStr(cast(string)ICON_FA_GEAR, "Settings"), (uint font){ app.showSettingsContent(font); });
}

void updateGame(ref GameApp app) {
  float dt = (app.time[FRAMESTOP] - app.time[LASTFRAME]) / 100.0f;
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