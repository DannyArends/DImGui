/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import resources : injectResourceMeshes;
import world : World, loadWorld, saveWorld;

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

  app.onFrame = (float dt) {
    app.world.settleBlocks(dt);
    app.updateWorld(app.camera.lookat);
  };
}

void cleanupGame(ref GameApp app) { app.saveWorld(); }