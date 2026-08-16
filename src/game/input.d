/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : syncBlockInstances;
import camera : castRay, tryDrag, tryZoom, tryMove, drag, zoom;
import clouds : rainTick, settleRain, requestCloudRebuild;
import entity : updateSkeletons;
import game : GameApp;
import screenshot : saveScreenshot;
import timing : timed;
import jobs : craftJob, jobQueue;
import lights : updateSun;
import tool : handlePrimaryPress, handlePrimaryDrag, handlePrimaryRelease, handleSecondaryPress, handleSecondaryRelease, updateHoverHighlight;
import vram : queryVRAM;
import water : waterTick, flushWaterDirty, evaporateTick;
import world : regenerateWorld;

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
    if(symbol == SDLK_K) { jobQueue ~= craftJob("FlintKnapping"); }
    if(symbol == SDLK_L) { jobQueue ~= craftJob("AxeMaking"); }
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
    } else if(e.fingerID == app.camera.fingerIDs[0] && app.world.inventory.activeTool == ToolMode.Info) {
      app.camera.drag(e.dx * 200.0f, e.dy * 200.0f);
    }
  }
}

/** Handles all ImGui IO and SDL events */
void pollEvents(ref GameApp app) {
  if(app.trace) SDL_Log("pollEvents");
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    if(app.isImGuiInitialized) ImGui_ImplSDL3_ProcessEvent(&e);
    if(e.type == SDL_EVENT_QUIT) app.finished = true;
    if(e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED && e.window.windowID == SDL_GetWindowID(app)) { app.finished = true; }
    if(e.type == SDL_EVENT_WINDOW_RESTORED) { app.minimized = false; }
    if(e.type == SDL_EVENT_WINDOW_MINIMIZED) { app.minimized = true; }
    if(!app.gui.io.WantCaptureKeyboard) app.timed!handleKeyEvents(e);

    if(e.type == SDL_EVENT_MOUSE_MOTION && app.camera.isdrag[1] && !app.gui.io.WantCaptureMouse) app.tryDrag(e.motion.xrel, e.motion.yrel);
    if(e.type == SDL_EVENT_MOUSE_WHEEL && !app.gui.io.WantCaptureMouse) {
      if(app.camera.fps){
        app.tryMove(e.wheel.y>0?app.camera.forward():app.camera.back());
      } else { app.tryZoom(-e.wheel.y); }
    }

    version(Android) { if(!app.gui.io.WantCaptureMouse) app.timed!handleTouchEvents(e); }
  }
  if(app.regenerate) { app.regenerate = false; app.regenerateWorld(); }
}

/** Dispatch game tool input from CURRENT pointer state. Runs AFTER igNewFrame() */
double handleEvents(ref GameApp app) {
  if(app.trace) SDL_Log("handleEvents");
  auto io = app.gui.io;
  bool[2] down = [io.MouseDown[0] && !io.WantCaptureMouse, io.MouseDown[1] && !io.WantCaptureMouse];
  float[2] pos = [io.MousePos.x, io.MousePos.y];
  auto ray = app.camera.castRay(pos[0], pos[1]);
  app.updateHoverHighlight(ray);

  if(down[0] && !app.camera.wasDown[0]) { app.camera.isdrag[0] = true; app.camera.pressPos = pos; app.handlePrimaryPress(ray); }
  else if(down[0] && app.camera.wasDown[0]) { app.handlePrimaryDrag(ray); }
  else if(!down[0] && app.camera.wasDown[0]) { app.camera.isdrag[0] = false; app.handlePrimaryRelease(ray); }

  if(down[1] && !app.camera.wasDown[1]) { app.camera.isdrag[1] = true; app.camera.pressPos = pos; app.handleSecondaryPress(ray); }
  else if(!down[1] && app.camera.wasDown[1]) {
    app.camera.isdrag[1] = false;
    auto dx = pos[0] - app.camera.pressPos[0]; auto dy = pos[1] - app.camera.pressPos[1];
    if((dx*dx + dy*dy) < 64) app.handleSecondaryRelease(ray);  // tap, not a drag
  }

  app.camera.wasDown = down;

  if(!app.paused && app.timeScale > 0 && app.time[FRAMESTART] - app.time[LASTTICK] > 250) {
    app.time[LASTTICK] = app.time[FRAMESTART];
    if(app.trace) SDL_Log("Tick[%d]: Frame: %d", app.paused, app.totalFramesRendered);
    app.timed!rainTick();             // spawn new falling drops
    app.timed!settleRain();           // convert any that have landed this tick
    app.timed!waterTick();            // sim the resulting water
    app.timed!evaporateTick();        // sim the resulting water
    app.timed!flushWaterDirty();      // re-mesh chunks whose water moved
    app.timed!requestCloudRebuild();  // Request a cloud update
    foreach(i; iota(app.objects.length)) {
      if(app.trace) SDL_Log("object: %s", toStringz(app.objects[i].geometry()));
      if(app.objects[i].onTick) app.objects[i].onTick();
    }
    app.updateSun();
    app.queryVRAM();
  }

  // Call all onFrame() handlers
  float dt = app.paused ? 0.0f : app.timeScale * ((app.time[FRAMESTOP] - app.time[LASTFRAME]) / 1000.0f);
  if(app.trace) SDL_Log("onFrame: Frame: %d", app.totalFramesRendered);
  foreach(object; app.objects) { if(object.onFrame) object.onFrame(dt); }   // Execute all onFrame() on Geometries
  if(app.camera.onFrame !is null) app.camera.onFrame(dt);                   // Execute onFrame() on Camera
  if(app.world.drops.dirty) { app.world.syncBlockInstances(); app.world.drops.dirty = false; }
  return(dt);
}
