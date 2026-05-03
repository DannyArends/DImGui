/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : settleBlocks;
import boundingbox : computeBoundingBox;
import camera : move, drag, zoom, castRay, tryMove;
import chunk : getBestTile;
import geometry : deAllocate, setColor;
import imgui : initializeImGui, saveSettings;
import intersection : intersects;
import line : createLine;
import lights : updateLightGeometries;
import screenshot : saveScreenshot;
import surface : createSurface;
import vulkan : cleanup;
import window: createOrResizeWindow;
import ghost : getGhostTile, updateGhostTile, syncBuildGhosts;
import inventory : placeTile, computeDragPreview;
import tree : getBestTree;
import timing : timed;
import mouse : handleMouseEvents;
import touch : handleTouchEvents;
import world : noTile;
import jobs : tryAssign, jobQueue, miningJob, woodcuttingJob;

/** Handle keyboard events */
void handleKeyEvents(ref App app, SDL_Event e) {
  if(e.type == SDL_EVENT_KEY_DOWN) {
    auto symbol = e.key.key;
    if(symbol == SDLK_PAGEUP) app.tryMove([ 0.0f,  1.0f, 0.0f]);
    if(symbol == SDLK_PAGEDOWN) app.tryMove([ 0.0f, -1.0f, 0.0f]);
    if(symbol == SDLK_P) app.paused = !app.paused;
    if(symbol == SDLK_W || symbol == SDLK_UP) app.tryMove(app.camera.forward());
    if(symbol == SDLK_S || symbol == SDLK_DOWN) app.tryMove(app.camera.back());
    if(symbol == SDLK_A || symbol == SDLK_LEFT) app.tryMove(app.camera.left());
    if(symbol == SDLK_D || symbol == SDLK_RIGHT) app.tryMove(app.camera.right());
    if(symbol == SDLK_F12) { app.saveScreenshot(); }
  }
}

/** Deallocate and removes stale Geometry from the app.objects array */
void removeGeometry(ref App app) {
  size_t[] idx;
  foreach(i, ref object; app.objects) { if(object.deAllocate) { app.deAllocate(object); idx ~= i; } }
  foreach(i; idx.reverse) { app.objects = app.objects.remove(i); }
}

/** Handles all ImGui IO and SDL events */
void handleEvents(ref App app) {
  if(app.trace) SDL_Log("handleEvents");
  SDL_Event e;
  ulong t0 = SDL_GetTicks();
  while (SDL_PollEvent(&e)) {
    if(SDL_GetTicks()-t0 > 2) SDL_Log("SLOW SDL_PollEvent=%dms", SDL_GetTicks()-t0);

    t0 = SDL_GetTicks();
    if(app.isImGuiInitialized) ImGui_ImplSDL3_ProcessEvent(&e);
    if(SDL_GetTicks()-t0 > 2) SDL_Log("SLOW ImGui_ImplSDL3_ProcessEvent=%dms", SDL_GetTicks()-t0);
    if(e.type == SDL_EVENT_QUIT) app.finished = true;
    if(e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED && e.window.windowID == SDL_GetWindowID(app)) { app.finished = true; }
    if(e.type == SDL_EVENT_WINDOW_RESTORED) { app.minimized = false; }
    if(e.type == SDL_EVENT_WINDOW_MINIMIZED) { app.minimized = true; }
    if(!app.gui.io.WantCaptureKeyboard) app.timed!handleKeyEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.timed!handleMouseEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.timed!handleTouchEvents(e);
  }

  if(app.paused) return;
  if(app.time[FRAMESTART] - app.time[LASTTICK] > 250) {
    app.time[LASTTICK] = app.time[FRAMESTART];
    if(app.trace) SDL_Log("Tick: Frame: %d", app.totalFramesRendered);
    t0 = SDL_GetTicks();
    foreach(i; iota(app.objects.length)) {
      if(app.trace) SDL_Log("object: %s", toStringz(app.objects[i].geometry()));
      ulong t1 = SDL_GetTicks();
      if(app.objects[i].onTick) app.objects[i].onTick(app, app.objects[i]);
      if(SDL_GetTicks()-t1 > 2) SDL_Log("SLOW onTick %s=%dms", toStringz(app.objects[i].geometry()), SDL_GetTicks()-t0);
    }
    if(SDL_GetTicks()-t0 > 2) SDL_Log("SLOW app.objects.onTick=%dms", SDL_GetTicks()-t0);
  }

  // Call all onFrame() handlers
  float dt = (app.time[FRAMESTOP] - app.time[LASTFRAME]) / 100.0f;
  if(app.trace) SDL_Log("onFrame: Frame: %d", app.totalFramesRendered);

  t0 = SDL_GetTicks();
  app.world.settleBlocks(app.world.blocks, dt);
  

  t0 = SDL_GetTicks();
  foreach(object; app.objects) { if(object.onFrame) object.onFrame(app, object, dt); }
  if(SDL_GetTicks()-t0 > 2) SDL_Log("SLOW onFrame=%dms", SDL_GetTicks()-t0);
}

/** sdlEventsFilter, return 1: Event go into the SDL_PollEvent queue, 0: If the event was handled immediately. 
 * Android *requires* us to handle the application events, for now we just pauze on enter background, since we 
 * need to ask for permission from the Android OS to run in the background. */
extern(C) bool sdlEventsFilter(void* userdata, SDL_Event* event) {
  if(!event) return(0);
  try {
    App* app = cast(App*)(userdata);
    switch (event.type) {
      case SDL_EVENT_TERMINATING: case SDL_EVENT_QUIT: 
      (*app).cleanup(); exit(0); // Run cleanup and exit
      break;
      case SDL_EVENT_LOW_MEMORY:
      case SDL_EVENT_WILL_ENTER_BACKGROUND: case SDL_EVENT_DID_ENTER_BACKGROUND:
      case SDL_EVENT_WILL_ENTER_FOREGROUND: case SDL_EVENT_DID_ENTER_FOREGROUND:
      SDL_Log(toStringz(format("Android SDL immediate event hook: %s", event.type)));
      (*app).handleApp(*event); return(0);

      default: return(1);
    }
  } catch (Exception err){ SDL_Log("Hook error: %d", toStringz(err.msg)); }
  return(1);
}

/** Immediate events handled by the application (Android filtered SDL immediate events)
 * SDL_EVENT_WILL_ENTER_BACKGROUND, SDL_EVENT_DID_ENTER_BACKGROUND, SDL_EVENT_WILL_ENTER_FOREGROUND, SDL_EVENT_DID_ENTER_FOREGROUND */
void handleApp(ref App app, const SDL_Event e) {
  if(e.type == SDL_EVENT_WILL_ENTER_BACKGROUND){
    SDL_Log("Suspending, wait on device idle & swapchain deletion queue");
    enforceVK(vkDeviceWaitIdle(app.device));
    app.swapDeletionQueue.flush(); // Frame deletion queue, flushes the buffers

    SDL_Log("Save ImGui Settings");
    saveSettings();
  }
  if(e.type == SDL_EVENT_DID_ENTER_BACKGROUND){
    SDL_Log("Completely in background, shutdown ImGui...");
    app.isImGuiInitialized = false;
    ImGui_ImplVulkan_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    igDestroyContext(null);

    SDL_Log("Destroy swapChain and Surface");
    vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator);
    app.swapChain = null;
    vkDestroySurfaceKHR(app.instance, app.surface, app.allocator); // Before destroying the Surface
    app.surface = null;

    app.minimized = true;
  }
  if(e.type == SDL_EVENT_WILL_ENTER_FOREGROUND){ SDL_Log("Resuming."); }
  if(e.type == SDL_EVENT_DID_ENTER_FOREGROUND){
    SDL_Log("Back in foreground, recreate surface, swapchain, and imgui.");
    app.gui.fonts.length = 0;
    app.createSurface();                                          /// Create Vulkan rendering surface
    app.createOrResizeWindow();                                   /// Create window (swapchain, renderpass, framebuffers, etc)
    app.initializeImGui();                                        /// Initialize ImGui (IO, Style, etc)
    app.minimized = false;
  }
}
