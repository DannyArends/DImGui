/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import camera : castRay, tryDrag, tryZoom, tryMove, drag, zoom;
import game : GameApp;
import hits : getHits;
import screenshot : saveScreenshot;
import timing : timed;
import lights : updateSun;
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
    app.updateHoverHighlight(e.button.x, e.button.y);
  }
  if(e.type == SDL_EVENT_MOUSE_MOTION) {
    if(app.camera.isdrag[1]) app.tryDrag(e.motion.xrel, e.motion.yrel);
    app.updateHoverHighlight(e.motion.x, e.motion.y);
    if(app.camera.isdrag[0]) app.handlePrimaryDrag(e.motion.x, e.motion.y);
  }
  if(e.type == SDL_EVENT_MOUSE_WHEEL) app.tryZoom(-e.wheel.y);
}

/** Handle keyboard events */
void handleKeyEvents(ref GameApp app, SDL_Event e) {
  if(e.type == SDL_EVENT_KEY_DOWN) {
    auto symbol = e.key.key;
    if(symbol == SDLK_PAGEUP) app.tryMove([ 0.0f,  1.0f, 0.0f]);
    if(symbol == SDLK_PAGEDOWN) app.tryMove([ 0.0f, -1.0f, 0.0f]);
    if(symbol == SDLK_P || symbol == SDLK_SPACE) app.paused = !app.paused;
    if(symbol == SDLK_W || symbol == SDLK_UP) app.tryMove(app.camera.forward());
    if(symbol == SDLK_S || symbol == SDLK_DOWN) app.tryMove(app.camera.back());
    if(symbol == SDLK_A || symbol == SDLK_LEFT) app.tryMove(app.camera.left());
    if(symbol == SDLK_D || symbol == SDLK_RIGHT) app.tryMove(app.camera.right());
    if(symbol == SDLK_F12) { app.saveScreenshot(); }
  }
}

/** Handle (Android) touch events */
void handleTouchEvents(ref GameApp app, const SDL_Event event) {
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

/** Handles all ImGui IO and SDL events */
double handleEvents(ref GameApp app) {
  if(app.trace) SDL_Log("handleEvents");
  SDL_Event e, lastMotion;
  bool haveMotion = false;
  while (SDL_PollEvent(&e)) {
    if(app.isImGuiInitialized) ImGui_ImplSDL3_ProcessEvent(&e);
    if(e.type == SDL_EVENT_QUIT) app.finished = true;
    if(e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED && e.window.windowID == SDL_GetWindowID(app)) { app.finished = true; }
    if(e.type == SDL_EVENT_WINDOW_RESTORED) { app.minimized = false; }
    if(e.type == SDL_EVENT_WINDOW_MINIMIZED) { app.minimized = true; }
    if(e.type == SDL_EVENT_MOUSE_MOTION) { haveMotion = true; lastMotion = e; continue; }
    if(!app.gui.io.WantCaptureKeyboard) app.timed!handleKeyEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.timed!handleMouseEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.timed!handleTouchEvents(e);
  }
  // When the Mouse moved, we process one motion/frame
  if(haveMotion && !app.gui.io.WantCaptureMouse) app.timed!handleMouseEvents(lastMotion);

  if(!app.paused && app.time[FRAMESTART] - app.time[LASTTICK] > 250) {
    app.time[LASTTICK] = app.time[FRAMESTART];
    if(app.trace) SDL_Log("Tick: Frame: %d", app.totalFramesRendered);
    foreach(i; iota(app.objects.length)) {
      if(app.trace) SDL_Log("object: %s", toStringz(app.objects[i].geometry()));
      if(app.objects[i].onTick) app.objects[i].onTick();
    }
    app.updateSun();
  }

  // Call all onFrame() handlers
  float dt = app.paused ? 0.0f : app.timeScale * ((app.time[FRAMESTOP] - app.time[LASTFRAME]) / 1000.0f);
  if(app.trace) SDL_Log("onFrame: Frame: %d", app.totalFramesRendered);
  foreach(object; app.objects) { if(object.onFrame) object.onFrame(dt); }   // Execute all onFrame() on Geometries
  if(app.camera.onFrame !is null) app.camera.onFrame(dt);                   // Execute onFrame() on Camera
  return(dt);
}
