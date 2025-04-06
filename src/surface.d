import engine;

void loadSurfaceCapabilities(ref App app) {
  uint formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(app.physicalDevice, app.surface, &app.capabilities));  // Capabilities

  // Surface formats
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, null));
  app.surfaceformats.length = formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, &app.surfaceformats[0]));

  SDL_Log("[SurfaceCapabilities] formatCount: %d", formatCount);
}
