/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

void querySurfaceCapabilities(ref App app) {
  uint formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(app.physicalDevice, app.surface, &app.camera.capabilities));  // Capabilities

  // Surface formats
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, null));
  app.surfaceformats.length = formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, &app.surfaceformats[0]));

  if(app.verbose) SDL_Log("[SurfaceCapabilities] formatCount: %d", formatCount);
}

void createSurface(ref App app) {
  SDL_Vulkan_CreateSurface(app, app.instance, &app.surface);

  app.mainDeletionQueue.add((){
    vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator); // We need to destoy the SwapChain
    vkDestroySurfaceKHR(app.instance, app.surface, app.allocator); // Before destroying the Surface
  });
  if(app.verbose) SDL_Log("SDL_Vulkan_CreateSurface: %p", app.surface);
}

