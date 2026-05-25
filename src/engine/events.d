/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import camera : tryMove;
import buffer : deAllocate;
import imgui : initializeImGui, saveSettings;
import screenshot : saveScreenshot;
import surface : createSurface;
import timing : timed;
import vulkan : cleanup;
import window : createOrResizeWindow;

/** Deallocate and removes stale Geometry from the app.objects array */
void removeGeometry(ref App app) {
  size_t[] idx;
  foreach(i, ref object; app.objects) { if(object.deAllocate) { app.deAllocate(object); idx ~= i; } }
  foreach(i; idx.reverse) { app.objects = app.objects.remove(i); }
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
