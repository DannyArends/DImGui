/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import camera : tryDrag, tryZoom, tryMove;
import deletion : deAllocate;
import imgui : initializeImGui, saveSettings;
import screenshot : saveScreenshot;
import surface : createSurface;
import timing : timed;
import vector : normalize, vAdd, vSub, vMul, magnitude;
import vulkan : cleanup;
import window : createOrResizeWindow;

/** Deallocate and removes stale Geometry from the app.objects array */
void removeGeometry(ref App app) {
  size_t[] idx;
  foreach(i, ref object; app.objects) { if(object.deAllocate) { app.deAllocate(object); idx ~= i; } }
  foreach(i; idx.reverse) { app.objects = app.objects.remove(i); }
}

/** Engine event pump: window, ImGui, camera. Game layers via app.onEvent. */
void pollEvents(ref App app) {
  if(app.trace) SDL_Log("pollEvents");
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    if(app.isImGuiInitialized) ImGui_ImplSDL3_ProcessEvent(&e);
    if(e.type == SDL_EVENT_QUIT) app.finished = true;
    if(e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED && e.window.windowID == SDL_GetWindowID(app)) app.finished = true;
    if(e.type == SDL_EVENT_WINDOW_RESTORED)  app.minimized = false;
    if(e.type == SDL_EVENT_WINDOW_MINIMIZED) app.minimized = true;

    if(!app.gui.io.WantCaptureKeyboard) app.timed!handleCameraKeys(e);
    if(e.type == SDL_EVENT_MOUSE_MOTION && app.camera.isdrag[1] && !app.gui.io.WantCaptureMouse) { 
      app.camera.dragAccum[0] += e.motion.xrel;
      app.camera.dragAccum[1] += e.motion.yrel;
    }
    if(e.type == SDL_EVENT_MOUSE_WHEEL && !app.gui.io.WantCaptureMouse) {
      if(!app.camera.fps) app.tryZoom(-e.wheel.y);
    }

    if(app.onEvent) app.onEvent(e);                                            // game: touch, game keys, tools
  }
}


/** Per-frame camera update: poll held keys (dt-scaled), then track the follow target. */
void updateCamera(ref App app, float dt) {
  auto k = SDL_GetKeyboardState(null);
  float[3] pan = [0.0f, 0.0f, 0.0f];
  if(k[SDL_SCANCODE_W] || k[SDL_SCANCODE_UP]) pan = pan.vAdd(app.camera.forward);
  if(k[SDL_SCANCODE_S] || k[SDL_SCANCODE_DOWN]) pan = pan.vSub(app.camera.forward);
  if(k[SDL_SCANCODE_D] || k[SDL_SCANCODE_RIGHT]) pan = pan.vAdd(app.camera.right);
  if(k[SDL_SCANCODE_A] || k[SDL_SCANCODE_LEFT]) pan = pan.vSub(app.camera.right);
  if(k[SDL_SCANCODE_PAGEUP]) pan[1] += 1.0f;
  if(k[SDL_SCANCODE_PAGEDOWN]) pan[1] -= 1.0f;
  if(pan.magnitude() > 1e-6f) {
    if(app.camera.mode == CameraMode.follow) app.camera.stopFollow();
    app.tryMove(pan.normalize().vMul(app.camera.speed * dt));
  }
  if(app.camera.dragAccum[0] != 0.0f || app.camera.dragAccum[1] != 0.0f) {
    app.tryDrag(app.camera.dragAccum[0] * app.camera.sensitivity, app.camera.dragAccum[1] * app.camera.sensitivity);
    app.camera.dragAccum = [0.0f, 0.0f];
  }
  if(app.camera.mode == CameraMode.follow) {
    float[3] target;
    if(app.camera.follow !is null && app.camera.follow(target)) {
      app.camera.lookat = target; app.camera.isDirty = true;
    } else { app.camera.stopFollow(); }
  }
}

/** Engine keyboard: camera navigation + pause. */
void handleCameraKeys(ref App app, SDL_Event e) {
  if(e.type != SDL_EVENT_KEY_DOWN) return;                 // held-key pan/rotate now polled in updateCamera
  if(e.key.key == SDLK_P || e.key.key == SDLK_SPACE) app.paused = !app.paused;
}

/** Pure engine frame timer (extracted from handleEvents). */
@nogc double frameDelta(ref App app) nothrow {
  return app.paused ? 0.0 : app.speed * ((app.time[FRAMESTOP] - app.time[LASTFRAME]) / 1000.0f);
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
      SDL_Log(cstr("Android SDL immediate event hook: %s", event.type));
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
