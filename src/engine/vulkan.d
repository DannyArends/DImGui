/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : saveSettings;
import geometry : cleanup;

/** Shutdown ImGui and deAllocate all vulkan related objects in existance
 */
void cleanup(App app) {
  SDL_Log("Wait on device idle & swapchain deletion queue");
  enforceVK(vkDeviceWaitIdle(app.device));
  app.swapDeletionQueue.flush();  // Delete SwapChain associated resources

  if (app.isImGuiInitialized) {
    SDL_Log("Save ImGui Settings");
    saveSettings();

    SDL_Log("Shutdown ImGui");
    ImGui_ImplVulkan_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    igDestroyContext(null);
  }
  SDL_Log("Delete all Geometry objects");
  foreach(object; app.objects) { app.cleanup(object); }

  SDL_Log("Flush the main deletion queue");
  app.mainDeletionQueue.flush();  // Delete permanent Vulkan resources

  SDL_Log("Joining Threads");
  thread_joinAll();

  SDL_Log("Destroying Window & Quit SDL");
  SDL_DestroyWindow(app);
  SDL_Quit();
}