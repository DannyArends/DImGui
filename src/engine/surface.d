/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

void printSurfaceFormat(const VkSurfaceFormatKHR fmt) {
  switch (fmt.format) {
    case VK_FORMAT_UNDEFINED: SDL_Log("format: VK_FORMAT_UNDEFINED"); break;
    case VK_FORMAT_R5G6B5_UNORM_PACK16: SDL_Log("format: VK_FORMAT_R5G6B5_UNORM_PACK16"); break;
    case VK_FORMAT_R8G8B8A8_UNORM: SDL_Log("format: VK_FORMAT_R8G8B8A8_UNORM"); break;
    case VK_FORMAT_B8G8R8A8_UNORM: SDL_Log("format: VK_FORMAT_B8G8R8A8_UNORM"); break;
    case VK_FORMAT_R8G8B8A8_SRGB: SDL_Log("format: VK_FORMAT_R8G8B8A8_SRGB"); break;
    case VK_FORMAT_R8G8B8_UNORM: SDL_Log("format: VK_FORMAT_R8G8B8_UNORM"); break;
    case VK_FORMAT_B8G8R8A8_SRGB: SDL_Log("format: VK_FORMAT_B8G8R8A8_SRGB"); break;
    case VK_FORMAT_R16G16B16A16_SFLOAT: SDL_Log("format: VK_FORMAT_R16G16B16A16_SFLOAT"); break;
    case VK_FORMAT_A2B10G10R10_UNORM_PACK32: SDL_Log("format: VK_FORMAT_A2B10G10R10_UNORM_PACK32"); break;
    default: SDL_Log("format: Unknown (%d)", fmt.format); break;
  }
  switch (fmt.colorSpace) {
    case VK_COLOR_SPACE_SRGB_NONLINEAR_KHR: SDL_Log("colorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR"); break;
    case VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT: SDL_Log("colorSpace: VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT"); break;
    default: SDL_Log("colorSpace: Unknown (%d)", fmt.colorSpace); break;
  }
}

int isSupported(ref App app, VkFormat requested){
  int s = -1;
  foreach(i, fmt; app.surfaceformats) { if(fmt.format == requested) s = cast(int)(i); }
  return(s);
}

void querySurfaceFormats(ref App app) {
  uint formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(app.physicalDevice, app.surface, &app.camera.capabilities));  // Capabilities

  if(app.verbose) SDL_Log("Capablities: ImageCount: %d - %d", app.camera.capabilities.minImageCount, app.camera.capabilities.maxImageCount);

  // Surface formats
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, null));
  app.surfaceformats.length = formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, &app.surfaceformats[0]));

  if(app.verbose){
    SDL_Log("[SurfaceCapabilities] formatCount: %d", formatCount);
    foreach(fmt; app.surfaceformats){
      fmt.printSurfaceFormat();
    }
  }
}

bool queryDeviceFormats(ref App app, VkFormat requested = VK_FORMAT_R16G16B16A16_SFLOAT) {
  VkFormatProperties formatProperties;
  vkGetPhysicalDeviceFormatProperties(app.physicalDevice, requested, &formatProperties);
  if (formatProperties.optimalTilingFeatures & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT &&
      formatProperties.optimalTilingFeatures & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT) {
    return(true);
  }
  return(false);
}

VkFormat getBestColorFormat(ref App app){
  auto ordering = [VK_FORMAT_R32G32B32A32_SFLOAT, VK_FORMAT_R16G16B16A16_SFLOAT, VK_FORMAT_R8G8B8A8_UNORM];
  version(Android){
    ordering = [VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_R16G16B16A16_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT];
  }
  foreach(format; ordering){
    if(app.queryDeviceFormats(format)){
      return(app.colorFormat = format);
    }
  }
  assert(0, "No suitable format found");
}

void createSurface(ref App app) {
  SDL_Vulkan_CreateSurface(app, app.instance, &app.surface);

  app.mainDeletionQueue.add((){
    vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator); // We need to destoy the SwapChain
    vkDestroySurfaceKHR(app.instance, app.surface, app.allocator); // Before destroying the Surface
  });
  if(app.verbose) SDL_Log("SDL_Vulkan_CreateSurface: %p", app.surface);
}

