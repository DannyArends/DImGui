/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import boundingbox : computeBoundingBox;
import camera : castRay, tryDrag, tryZoom;
import geometry : setColor;
import ghost : updateGhostTile;
import intersection : intersects;
import line : createLine;
import tool : handlePrimaryPress, handlePrimaryDrag, handlePrimaryRelease, handleSecondaryPress, updateHoverHighlight;

/** Handle mouse events */
void handleMouseEvents(ref App app, SDL_Event e) {
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
    app.updateGhostTile(ray);
  }
  if(e.type == SDL_EVENT_MOUSE_MOTION) {
    if(app.camera.isdrag[1]) app.tryDrag(e.motion.xrel, e.motion.yrel);
    app.updateGhostTile(ray);
    if(app.camera.isdrag[0]) app.handlePrimaryDrag(e.motion.x, e.motion.y);
    else app.updateHoverHighlight(e.motion.x, e.motion.y);
  }
  if(e.type == SDL_EVENT_MOUSE_WHEEL) app.tryZoom(-e.wheel.y);
}

/** Get a list of intersections between the ray and the objects in the scene */
Intersection[] getHits(ref App app, float[3][2] ray, bool showRay = true) {
  Intersection[] hits;
  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isVisible) continue;
    if(!app.objects[x].isSelectable) continue;
    if(cast(Line)(app.objects[x]) !is null) continue;
    app.objects[x].computeBoundingBox(app.trace);
    auto intersections = ray.intersects(app.objects[x].box, x);
    app.objects[x].window = false;
    if(intersections.any!(i => i.intersects)) hits ~= intersections;
    else app.objects[x].box.setColor();
  }
  if(showRay) app.objects ~= createLine(ray);
  hits.sort!("a.tmin < b.tmin");
  return hits;
}