/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import camera : drag, zoom;

/** Handle (Android) touch events */
void handleTouchEvents(ref App app, const SDL_Event event) {
  SDL_TouchFingerEvent e = event.tfinger;
  if (event.type == SDL_EVENT_FINGER_DOWN) {
    if(app.camera.fingerIDs[0] == -1) { app.camera.fingerIDs[0] = e.fingerID; app.camera.fingerPos[0] = [e.x, e.y]; }
    else if(app.camera.fingerIDs[1] == -1) { app.camera.fingerIDs[1] = e.fingerID; app.camera.fingerPos[1] = [e.x, e.y]; app.camera.lastPinchDist = -1.0f; }
  }
  if (event.type == SDL_EVENT_FINGER_UP) {
    if(e.fingerID == app.camera.fingerIDs[0]) { app.camera.fingerIDs[0] = -1; app.camera.lastPinchDist = -1.0f; }
    if(e.fingerID == app.camera.fingerIDs[1]) { app.camera.fingerIDs[1] = -1; app.camera.lastPinchDist = -1.0f; }
  }
  if (event.type == SDL_EVENT_FINGER_MOTION) {
    if(e.fingerID == app.camera.fingerIDs[0]) app.camera.fingerPos[0] = [e.x, e.y];
    if(e.fingerID == app.camera.fingerIDs[1]) app.camera.fingerPos[1] = [e.x, e.y];
    bool twoFingers = app.camera.fingerIDs[0] != -1 && app.camera.fingerIDs[1] != -1;
    if (twoFingers) {
      float dx = app.camera.fingerPos[1][0] - app.camera.fingerPos[0][0];
      float dy = app.camera.fingerPos[1][1] - app.camera.fingerPos[0][1];
      float dist = sqrt(dx*dx + dy*dy);

      if(app.camera.lastPinchDist > 0.0f) { app.camera.zoom((app.camera.lastPinchDist - dist) * 60.0f); }
      app.camera.lastPinchDist = dist;
    } else if(e.fingerID == app.camera.fingerIDs[0]) { app.camera.drag(e.dx * 200.0f, e.dy * 200.0f); }
  }
}
