/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.algorithm : remove, reverse;

import commands : recordRenderCommandBuffer;
import camera : move, drag, castRay;
import geometry : deAllocate;
import line : createLine;
import sdl : FRAMESTART, LASTTICK;

void handleKeyEvents(ref App app, SDL_Event e) {
  if(e.type == SDL_KEYDOWN) {
    auto symbol = e.key.keysym.sym;
    if(symbol == SDLK_PAGEUP){ app.camera.move([ 0.0f,  1.0f, 0.0f]); }
    if(symbol == SDLK_PAGEDOWN){ app.camera.move([ 0.0f,  -1.0f, 0.0f]); }
    if(symbol == SDLK_w || symbol == SDLK_UP){ app.camera.move(app.camera.forward()); }
    if(symbol == SDLK_s || symbol == SDLK_DOWN){ app.camera.move(app.camera.back());  }
    if(symbol == SDLK_a || symbol == SDLK_LEFT){ app.camera.move(app.camera.left());  }
    if(symbol == SDLK_d || symbol == SDLK_RIGHT){ app.camera.move(app.camera.right());  }
  }
}

void handleMouseEvents(ref App app, SDL_Event e) {
  if(e.type == SDL_MOUSEBUTTONDOWN){
    if (e.button.button == SDL_BUTTON_LEFT) { 
      app.camera.isdrag[0] = true;
      app.objects ~= createLine(app.camera.castRay(e.motion.x, e.motion.y));
    }
    if (e.button.button == SDL_BUTTON_RIGHT) { app.camera.isdrag[1] = true;}
  }
  if(e.type == SDL_MOUSEBUTTONUP){
    if (e.button.button == SDL_BUTTON_LEFT) { app.camera.isdrag[0] = false; }
    if (e.button.button == SDL_BUTTON_RIGHT) { app.camera.isdrag[1] = false;}
  }
  if(e.type == SDL_MOUSEMOTION){
    if(app.camera.isdrag[1]) app.camera.drag(e.motion.xrel, e.motion.yrel);
  }
  if(e.type == SDL_MOUSEWHEEL){
    if (e.wheel.y < 0 && app.camera.distance <= 60.0f) app.camera.distance += 0.5f;
    if (e.wheel.y > 0 && app.camera.distance >=  2.0f) app.camera.distance -= 0.5f;
    app.camera.move([ 0.0f,  0.0f,  0.0f]);
  }
}

/** Deallocate and removes stale Geometry from the app.objects array
 */
void removeGeometry(ref App app) {
  size_t[] idx;
  foreach(i, object; app.objects) { if(object.deAllocate){ app.deAllocate(object); idx ~= i; } }
  foreach(i; idx.reverse) { app.objects = app.objects.remove(i); }
}

/** Handles all ImGui IO and SDL events
 */
void handleEvents(ref App app) {
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    ImGui_ImplSDL2_ProcessEvent(&e);
    if(e.type == SDL_QUIT) app.finished = true;
    if(e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_CLOSE && e.window.windowID == SDL_GetWindowID(app)) app.finished = true;
    if(!app.io.WantCaptureKeyboard) app.handleKeyEvents(e);
    if(!app.io.WantCaptureMouse) app.handleMouseEvents(e);
  }

  if(app.time[FRAMESTART] - app.time[LASTTICK] > 10000) {
    app.time[LASTTICK] = app.time[FRAMESTART];
    if(app.verbose) SDL_Log("10 seconds: Frame: %d", app.totalFramesRendered);
    foreach(object; app.objects) { if(object.onTick) object.onTick(app, object); }
  }

  // Call all onFrame() handlers
  foreach(object; app.objects) { if(object.onFrame) object.onFrame(app, object); }

  // Make sure we remove stale geometry and record the command buffer every frame after handling events
  enforceVK(vkDeviceWaitIdle(app.device));
  app.removeGeometry();
  app.recordRenderCommandBuffer();
}
