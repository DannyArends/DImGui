/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : settleBlocks;
import boundingbox : computeBoundingBox;
import camera : move, drag, zoom, castRay, tryMove, tryDrag, tryZoom;
import chunk : getBestTile, setTile;
import geometry : deAllocate, setColor;
import imgui : initializeImGui, saveSettings;
import intersection : intersects;
import line : createLine;
import lights : updateLightGeometries;
import screenshot : saveScreenshot;
import surface : createSurface;
import vulkan : cleanup;
import window: createOrResizeWindow;
import ghost : getGhostTile, updateGhostTile;
import inventory : placeTile;
import tree : getBestTree;
import world : noTile;
import jobs : tryAssign, jobQueue, miningJob, woodcuttingJob;

/** Handle keyboard events */
void handleKeyEvents(ref App app, SDL_Event e) {
  if(e.type == SDL_EVENT_KEY_DOWN) {
    auto symbol = e.key.key;
    if(symbol == SDLK_PAGEUP) app.tryMove([ 0.0f,  1.0f, 0.0f]);
    if(symbol == SDLK_PAGEDOWN) app.tryMove([ 0.0f, -1.0f, 0.0f]);
    if(symbol == SDLK_W || symbol == SDLK_UP) app.tryMove(app.camera.forward());
    if(symbol == SDLK_S || symbol == SDLK_DOWN) app.tryMove(app.camera.back());
    if(symbol == SDLK_A || symbol == SDLK_LEFT) app.tryMove(app.camera.left());
    if(symbol == SDLK_D || symbol == SDLK_RIGHT) app.tryMove(app.camera.right());
    if(symbol == SDLK_F12) { app.saveScreenshot(); }
  }
}

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

/** Get a list of intersections between the ray and the objects in the scene */
Intersection[] getHits(ref App app, float[3][2] ray, bool showRay = true){
  Intersection[] hits;

  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isVisible) continue;                       // Invisible objects should not generate hits
    if(!app.objects[x].isSelectable) continue;                    // Non-selectable objects should not generate hits
    if(cast(Line)(app.objects[x]) !is null) continue;             // Lines should not generate hits
    app.objects[x].computeBoundingBox(app.trace);                 // Make sure we compute the current Bounding Box
    auto intersections = ray.intersects(app.objects[x].box, x);   // Compute the intersection
    app.objects[x].window = false;
    if (intersections.any!(i => i.intersects)) {
      //version(Android) {} else { app.gui.showObjects = true; }
      hits ~= intersections;
    } else { app.objects[x].box.setColor(); }
  }
  if(showRay) app.objects ~= createLine(ray);
  hits.sort!("a.tmin < b.tmin");
  return(hits);
}

/** Handle mouse events */
void handleMouseEvents(ref App app, SDL_Event e) {
  app.camera.lastMousePos = [app.gui.io.MousePos.x, app.gui.io.MousePos.y];
  auto ray = app.camera.castRay(app.camera.lastMousePos[0], app.camera.lastMousePos[1]);

  if(e.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
    if (e.button.button == SDL_BUTTON_LEFT) { 
      app.camera.isdrag[0] = true;
      app.camera.lastMousePos = [e.button.x, e.button.y];
    }
    if (e.button.button == SDL_BUTTON_RIGHT) { 
      app.camera.isdrag[1] = true;
      app.camera.lastMousePos = [e.button.x, e.button.y];
    }
  }
  if(e.type == SDL_EVENT_MOUSE_BUTTON_UP) {
    app.camera.isdrag[0] = false; 
    if (e.button.button == SDL_BUTTON_LEFT) {
      if(app.inventory.ghostTile[0] != int.min) {
        app.placeTile(app.inventory.ghostTile);
      } else {
        auto hits = app.getHits(ray, app.showRays);
        if(hits.length > 0) {
          int[3] wc;
          Job job;
          if(app.getBestTree(ray, hits, wc)) {
            job = woodcuttingJob(wc);
          }else if(app.getBestTile(ray, wc)) {
            job = miningJob(wc);
          }
          if(job.name !is null && !app.tryAssign(job)) jobQueue ~= job;
        }
        foreach (ref hit; hits) {
          auto obj = app.objects[hit.idx[0]];
          if (cast(Chunk)obj is null) {
            obj.box.setColor(Colors.yellowgreen);
            obj.window = true;
            break;
          }
        }
      }
    }
    if (e.button.button == SDL_BUTTON_RIGHT) {
      app.inventory.selectedTile = TileType.None;
      app.camera.isdrag[1] = false;
    }
    app.updateGhostTile(ray);
  }
  if(e.type == SDL_EVENT_MOUSE_MOTION){ 
    if(app.camera.isdrag[1]) { app.tryDrag(e.motion.xrel, e.motion.yrel); }
    app.updateGhostTile(ray);
  }
  if(e.type == SDL_EVENT_MOUSE_WHEEL){ app.tryZoom(-e.wheel.y); }
}

/** Deallocate and removes stale Geometry from the app.objects array */
void removeGeometry(ref App app) {
  size_t[] idx;
  foreach(i, ref object; app.objects) {
    if(object.deAllocate) { app.deAllocate(object); idx ~= i; }
  }
  foreach(i; idx.reverse) { app.objects = app.objects.remove(i); }
}

/** Handles all ImGui IO and SDL events */
void handleEvents(ref App app) {
  if(app.trace) SDL_Log("handleEvents");
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    if(app.isImGuiInitialized) ImGui_ImplSDL3_ProcessEvent(&e);
    if(e.type == SDL_EVENT_QUIT) app.finished = true;
    if(e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED && e.window.windowID == SDL_GetWindowID(app)) { app.finished = true; }
    if(e.type == SDL_EVENT_WINDOW_RESTORED) { app.isMinimized = false; }
    if(e.type == SDL_EVENT_WINDOW_MINIMIZED) { app.isMinimized = true; }
    if(!app.gui.io.WantCaptureKeyboard) app.handleKeyEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.handleMouseEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.handleTouchEvents(e);
  }

  if(app.time[FRAMESTART] - app.time[LASTTICK] > 250) {
    app.updateLightGeometries();
    app.time[LASTTICK] = app.time[FRAMESTART];
    if(app.trace) SDL_Log("Tick: Frame: %d", app.totalFramesRendered);
    foreach(i; iota(app.objects.length)) {
      if(app.trace) SDL_Log("object: %s", toStringz(app.objects[i].geometry()));
      if(app.objects[i].onTick) app.objects[i].onTick(app, app.objects[i]); 
    }
  }

  // Call all onFrame() handlers
  float dt = (app.time[FRAMESTOP] - app.time[LASTFRAME]) / 100.0f;
  if(app.trace) SDL_Log("onFrame: Frame: %d", app.totalFramesRendered);
  app.world.settleBlocks(app.world.blocks, dt);
  foreach(object; app.objects) { if(object.onFrame) object.onFrame(app, object, dt); }
}

/** sdlEventsFilter, return 1: Event go into the SDL_PollEvent queue, 0: If the event was handled immediately. 
 Android *requires* us to handle the application events, for now we just pauze on enter background, since we 
 need to ask for permission from the Android OS to run in the background.
*/
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
SDL_EVENT_WILL_ENTER_BACKGROUND
SDL_EVENT_DID_ENTER_BACKGROUND
SDL_EVENT_WILL_ENTER_FOREGROUND
SDL_EVENT_DID_ENTER_FOREGROUND
*/
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

    app.isMinimized = true;
  }
  if(e.type == SDL_EVENT_WILL_ENTER_FOREGROUND){ SDL_Log("Resuming."); }
  if(e.type == SDL_EVENT_DID_ENTER_FOREGROUND){
    SDL_Log("Back in foreground, recreate surface, swapchain, and imgui.");
    app.gui.fonts.length = 0;
    app.createSurface();                                          /// Create Vulkan rendering surface
    app.createOrResizeWindow();                                   /// Create window (swapchain, renderpass, framebuffers, etc)
    app.initializeImGui();                                        /// Initialize ImGui (IO, Style, etc)
    app.isMinimized = false;
  }
}
