import includes;
import application : App;
import sdl : checkSDLError;
import vkdebug : enforceVK;

struct Surface {
  VkSurfaceKHR surface;
  VkSurfaceCapabilitiesKHR capabilities;
  VkSurfaceFormatKHR[] surfaceformats;
  VkPresentModeKHR[] presentModes;
  alias surface this;
}

void createSurface(ref App app) {
  SDL_Log("createSurface(app: %p, instance: %p)", app, app.instance);
  SDL_Vulkan_CreateSurface(app, app.instance, &app.surface.surface);
  checkSDLError();
  SDL_Log("SDL Vulkan Surface %p created", app.surface);
}

void loadSurfaceCapabilities(ref App app) {
  uint formatCount;
  uint presentModeCount;
  enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(app.physicalDevices[app.selected], app.surface, &app.surface.capabilities));  // Capabilities

  // Surface formats
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, null));
  app.surface.surfaceformats.length = formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, &app.surface.surfaceformats[0]));

  // Surface present modes
  enforceVK(vkGetPhysicalDeviceSurfacePresentModesKHR(app.physicalDevice, app.surface, &presentModeCount, null));
  app.surface.presentModes.length = presentModeCount;
  enforceVK(vkGetPhysicalDeviceSurfacePresentModesKHR(app.physicalDevice, app.surface, &presentModeCount, &app.surface.presentModes[0]));

  SDL_Log("formatCount: %d, presentModeCount: %d", formatCount, presentModeCount);
}
