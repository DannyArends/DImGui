/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import camera : castRay, tryDrag, tryZoom;
import ghost : updateGhostTile;
import tool : handlePrimaryPress, handlePrimaryDrag, handlePrimaryRelease, handleSecondaryPress, updateHoverHighlight;

/** Handle mouse events */
void handleMouseEvents(ref GameApp app, SDL_Event e) {
  app.camera.lastMousePos = [app.gui.io.MousePos.x, app.gui.io.MousePos.y];
  auto ray = app.camera.castRay(app.camera.lastMousePos[0], app.camera.lastMousePos[1]);

  if(e.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
    if(e.button.button == SDL_BUTTON_LEFT) {
      app.camera.isdrag[0] = true;
      app.camera.lastMousePos = [e.button.x, e.button.y];
      app.handlePrimaryPress(e.button.x, e.button.y);
    }
    if(e.button.button == SDL_BUTTON_RIGHT) {
      app.camera.isdrag[1] = true;
      app.camera.lastMousePos = [e.button.x, e.button.y];
      app.handleSecondaryPress(e.button.x, e.button.y);
    }
  }
  if(e.type == SDL_EVENT_MOUSE_BUTTON_UP) {
    app.camera.isdrag[0] = false;
    if(e.button.button == SDL_BUTTON_LEFT) app.handlePrimaryRelease(e.button.x, e.button.y);
    if(e.button.button == SDL_BUTTON_RIGHT) app.camera.isdrag[1] = false;
    auto hits = app.getHits(ray, false);
    app.updateGhostTile(ray, hits);
  }
  if(e.type == SDL_EVENT_MOUSE_MOTION) {
    if(app.camera.isdrag[1]) app.tryDrag(e.motion.xrel, e.motion.yrel);
    auto hits = app.getHits(ray, false);
    app.updateGhostTile(ray, hits);
    if(app.camera.isdrag[0]) app.handlePrimaryDrag(e.motion.x, e.motion.y);
  }
  if(e.type == SDL_EVENT_MOUSE_WHEEL) app.tryZoom(-e.wheel.y);
}
