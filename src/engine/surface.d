import engine;

void querySurfaceCapabilities(ref App app) {
  uint formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(app.physicalDevice, app.surface, &app.capabilities));  // Capabilities

  // Surface formats
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, null));
  app.surfaceformats.length = formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, &app.surfaceformats[0]));

  if(app.verbose) SDL_Log("[SurfaceCapabilities] formatCount: %d", formatCount);
}

void createSurface(ref App app) {
  SDL_Vulkan_CreateSurface(app, app.instance, &app.surface);
  if(app.verbose) SDL_Log("SDL_Vulkan_CreateSurface: %p", app.surface);
}

