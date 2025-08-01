/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import boundingbox : computeBoundingBox;
import commands : recordRenderCommandBuffer;
import camera : move, drag, castRay;
import geometry : deAllocate, setColor;
import imgui : saveSettings;
import intersection : intersects;
import line : createLine;
import surface : createSurface;
import vulkan : cleanup;
import window: createOrResizeWindow;
import imgui : initializeImGui;

/** Handle keyboard events
 */
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

/** Handle touch events
 */
void handleTouchEvents(ref App app, const SDL_Event event) {
  SDL_TouchFingerEvent e = event.tfinger;
  if(event.type == SDL_FINGERDOWN) {
    if(e.fingerId == 0) app.camera.isdrag[0] = true;
  }
  if(event.type == SDL_FINGERUP) {
    if(e.fingerId == 0) app.camera.isdrag[0] = false;
    app.camera.move(app.camera.forward());
  }
  if(event.type == SDL_FINGERMOTION) {
    if(app.verbose){
      SDL_Log("TouchMotion: %f %f [%f %f] by %.1f [%d]\n", e.x, e.y, e.dx * app.camera.width, e.dy * app.camera.height, e.pressure, e.fingerId);
    }
    if(e.fingerId == 1) {
      if (e.dy > 0 && app.camera.distance  <= 30.0f) app.camera.distance += 0.2f;
      if (e.dy < 0 && app.camera.distance  >= 2.0f) app.camera.distance -= 0.2f;
    }else{
      if(e.fingerId == 0) app.camera.drag(-e.dx * 0.5 * app.camera.width, e.dy * 0.25 * app.camera.height);
    }
  }
}

/** Get a list of intersections between the ray and the objects in the scene
 */
Intersection[] getHits(ref App app, SDL_Event e, bool showRay = true){
  auto ray = app.camera.castRay(e.motion.x, e.motion.y);
  Intersection[] hits;

  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isVisible) continue;                   // invisible objects should not generate hits
    if(app.objects[x].name() == "Line") continue;             // Other lines should not generate hits
    app.objects[x].computeBoundingBox(app.trace);             // Make sure we compute the current Bounding Box
    auto intersection = ray.intersects(app.objects[x].box);   // Compute the intersection
    app.objects[x].window = false;
    if (intersection.intersects) {
      intersection.idx = cast(uint)x;
      app.objects[x].box.setColor(Colors.paleturquoise);
      app.gui.showObjects = true;
      hits ~= intersection;
    }else{
      app.objects[x].box.setColor();
    }
  }
  if(showRay) app.objects ~= createLine(ray);
  hits.sort!("a.tmin < b.tmin");
  return(hits);
}

/** Handle mouse events
 */
void handleMouseEvents(ref App app, SDL_Event e) {
  if(e.type == SDL_MOUSEBUTTONDOWN){
    if (e.button.button == SDL_BUTTON_LEFT) { 
      app.camera.isdrag[0] = true;
    }
    if (e.button.button == SDL_BUTTON_RIGHT) { app.camera.isdrag[1] = true;}
  }
  if(e.type == SDL_MOUSEBUTTONUP){
    if (e.button.button == SDL_BUTTON_LEFT) { app.camera.isdrag[0] = false; }
    if (e.button.button == SDL_BUTTON_RIGHT) { app.camera.isdrag[1] = false; }
    auto hits = app.getHits(e, app.showRays);
    if (hits.length > 0) {
      if(app.verbose) SDL_Log("Clostest hit: %d = %s", hits[0].idx, toStringz(app.objects[hits[0].idx].name()));
      app.objects[hits[0].idx].box.setColor(Colors.yellowgreen);
      app.objects[hits[0].idx].window = true;
    }
  }
  if(e.type == SDL_MOUSEMOTION){
    if(app.camera.isdrag[1]) app.camera.drag(e.motion.xrel, e.motion.yrel);
  }
  if(e.type == SDL_MOUSEWHEEL){
    if (e.wheel.y < 0 && app.camera.distance <= 60.0f) app.camera.distance += 0.5f;
    if (e.wheel.y > 0 && app.camera.distance >=  2.0f) app.camera.distance -= 0.5f;
  }
}

/** Deallocate and removes stale Geometry from the app.objects array
 */
void removeGeometry(ref App app) {
  size_t[] idx;
  foreach(i, ref object; app.objects) {
    if(object.deAllocate) { app.deAllocate(object); idx ~= i; }
  }
  foreach(i; idx.reverse) { app.objects.array = app.objects.array.remove(i); }
}

/** Handles all ImGui IO and SDL events
 */
void handleEvents(ref App app) {
  if(app.trace) SDL_Log("handleEvents");
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    if(app.isImGuiInitialized) ImGui_ImplSDL2_ProcessEvent(&e);
    if(e.type == SDL_QUIT) app.finished = true;
    if(e.type == SDL_WINDOWEVENT) { 
      if(e.window.event == SDL_WINDOWEVENT_CLOSE && e.window.windowID == SDL_GetWindowID(app)){ app.finished = true; }
      if(e.window.event == SDL_WINDOWEVENT_RESTORED){ app.isMinimized = false; }
      if(e.window.event == SDL_WINDOWEVENT_MINIMIZED){ app.isMinimized = true; }
    }
    if(!app.gui.io.WantCaptureKeyboard) app.handleKeyEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.handleMouseEvents(e);
    if(!app.gui.io.WantCaptureMouse) app.handleTouchEvents(e);
  }

  if(app.time[FRAMESTART] - app.time[LASTTICK] > 2500) {
    //GC.collect();
    app.time[LASTTICK] = app.time[FRAMESTART];
    if(app.trace) SDL_Log("Tick: Frame: %d", app.totalFramesRendered);
    foreach(object; app.objects) {
      if(app.trace) SDL_Log("object: %s", toStringz(object.name()));
      if(object.onTick) object.onTick(app, object); 
    }
  }

  // Call all onFrame() handlers
  if(app.trace) SDL_Log("onFrame: Frame: %d", app.totalFramesRendered);
  float dt = (app.time[FRAMESTOP] - app.time[FRAMESTART]) / 100.0f;
  foreach(object; app.objects) { if(object.onFrame) object.onFrame(app, object, dt); }

  // Remove stale geometry
  app.removeGeometry();
}

/* sdlEventsFilter returns 1 will have the event go into the SDL_PollEvent queue, 0 if have handled 
   the event immediately. Android requires us to handle the application events, for now we just 
   shutdown on enter background, since we should properly ask for permission from the Android OS to 
   run in the background.
*/
extern(C) int sdlEventsFilter(void* userdata, SDL_Event* event) {
  if(!event) return(0);
  try {
    App* app = cast(App*)(userdata);
    switch (event.type) {
      case SDL_APP_TERMINATING: case SDL_QUIT: 
      (*app).cleanup(); exit(0); // Run cleanup and exit
      break;
      case SDL_APP_LOWMEMORY: 
      case SDL_APP_WILLENTERBACKGROUND: case SDL_APP_DIDENTERBACKGROUND:
      case SDL_APP_WILLENTERFOREGROUND: case SDL_APP_DIDENTERFOREGROUND:
      SDL_Log(toStringz(format("Android SDL immediate event hook: %s", event.type)));
      (*app).handleApp(*event); return(0);

      default: return(1);
    }
  } catch (Exception err){ SDL_Log("Hook error: %d", toStringz(err.msg)); }
  return(1);
}

// Immediate events to handle by the application
void handleApp(ref App app, const SDL_Event e) { 
  if(e.type == SDL_APP_WILLENTERBACKGROUND){ 
    SDL_Log("Suspending.");
    SDL_Log("Wait on device idle & swapchain deletion queue");
    enforceVK(vkDeviceWaitIdle(app.device));
    app.swapDeletionQueue.flush(); // Frame deletion queue, flushes the buffers

    SDL_Log("Save ImGui Settings");
    saveSettings();
  }
  if(e.type == SDL_APP_DIDENTERBACKGROUND){ 
    SDL_Log("Completely in background."); 
    SDL_Log("Shutdown ImGui");
    app.isImGuiInitialized = false;
    ImGui_ImplVulkan_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    igDestroyContext(null);

    SDL_Log("Destroy swapChain and Surface");
    vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator);
    app.swapChain = null;
    vkDestroySurfaceKHR(app.instance, app.surface, app.allocator); // Before destroying the Surface
    app.surface = null;

    app.isMinimized = true;
  }
  if(e.type == SDL_APP_WILLENTERFOREGROUND){ SDL_Log("Resuming."); }
  if(e.type == SDL_APP_DIDENTERFOREGROUND){ 
    SDL_Log("Back in foreground, recreate surface, swapchain, and imgui.");
    app.gui.fonts.length = 0;
    app.createSurface();                                          /// Create Vulkan rendering surface
    app.createOrResizeWindow();                                   /// Create window (swapchain, renderpass, framebuffers, etc)
    app.initializeImGui();                                        /// Initialize ImGui (IO, Style, etc)
    app.isMinimized = false;
  }
}
