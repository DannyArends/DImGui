/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : settleBlocks;
import dwarfwindow : showDwarfContent;
import imgui : iconText;
import inventorywindow : showInventoryContent;
import pathfinding : canMoveTo;
import resources : injectResourceMeshes;
import world : World, loadWorld, saveWorld;
import worldwindow : showWorldContent;

struct GameApp {
  App app;
  alias app this;  // GameApp usable everywhere App is expected

  World world;

  bool showPaths = false;
  bool showBounds = false;
  bool showRays = false;
  bool showLights = false;
  bool disco = false;
  bool paused = false;
}

void initGame(ref GameApp app) {
  app.loadWorld();
  app.injectResourceMeshes();
  app.camera.canMoveTo = (float[3] pos){ return app.world.canMoveTo(pos); };
  app.gameWindows ~= GameWindow(iconText(cast(string)ICON_FA_INBOX, "Inventory"), (uint font){ app.showInventoryContent(font); });
  app.gameWindows ~= GameWindow(iconText(cast(string)ICON_FA_GLOBE, "World"), (uint font){ app.showWorldContent(font); });
  app.gameWindows ~= GameWindow(iconText(cast(string)ICON_FA_USER, "Dwarfs"), (uint font){ app.showDwarfContent(font); });

  app.onFrame = (float dt) {
    app.world.settleBlocks(dt);
    app.updateWorld(app.camera.lookat);
  };
}

void cleanupGame(ref GameApp app) { app.saveWorld(); }