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

/** Create a vulkan surface */
void createSurface(ref App app) {
  SDL_Vulkan_CreateSurface(app.window, app.instance, null, &app.surface);

  app.mainDeletionQueue.add((){
    if(app.swapChain != null){ if(app.verbose) SDL_Log("Destroy Swapchain: %p", app.swapChain);
      vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator); // We need to destoy the SwapChain
    }
    if(app.surface != null){ if(app.verbose) SDL_Log("Destroy Surface: %p", app.surface);
      vkDestroySurfaceKHR(app.instance, app.surface, app.allocator); // Before destroying the Surface
    }
  });
  if(app.verbose) SDL_Log("SDL_Vulkan_CreateSurface: %p", app.surface);
}


/** Check file extension to determine if something is a texture */
bool isTexture(string path){
  auto ext = extension(path); if(ext == ".jpg" || ext == ".png"){ return(true); }
  return(false);
}

/** Convert an SDL-Surface to RGBA32 format */
void toRGBA(ref SDL_Surface* surface, uint verbose = 0) {
  SDL_Surface* adapted = SDL_ConvertSurface(surface, SDL_PIXELFORMAT_RGBA32);
  if (adapted) {
    SDL_DestroySurface(surface); // Free the SDL_Surface
    surface = adapted;
    if(verbose > 1) SDL_Log("Adapted: %p [%dx%d:%d]", surface, surface.w, surface.h, (SDL_GetPixelFormatDetails(surface.format).bytes_per_pixel));
  }
}

/** VRAM cap for a texture's longest side; data maps (AO/normal/rough) tolerate half the albedo resolution. */
int textureCap(string path) {
  int cap = isAndroid ? 1024 : 2048;
  foreach(suffix; ["_Ao", "_ao", "_Nor", "_nor", "_normal", "_Rough", "_rough", "_Metal", "_metal"]) { if(path.indexOf(suffix) >= 0) return(cap / 2); }
  return(cap);
}

/** Downscale an oversized surface in place to fit maxDim on its longest side (preserves aspect). */
void clampSurface(ref SDL_Surface* surface, int maxDim) {
  int m = (surface.w > surface.h) ? surface.w : surface.h;
  if(m <= maxDim) return;
  float s = cast(float)maxDim / m;
  int nw = cast(int)(surface.w * s + 0.5f); if(nw < 1) nw = 1;
  int nh = cast(int)(surface.h * s + 0.5f); if(nh < 1) nh = 1;
  SDL_Surface* scaled = SDL_ScaleSurface(surface, nw, nh, SDL_SCALEMODE_LINEAR);
  if(scaled) { SDL_DestroySurface(surface); surface = scaled; }
}

/** Create a 1x1 white SDL_Surface */
SDL_Surface* createDummySDLSurface() {
  SDL_Surface* surface = SDL_CreateSurface(1, 1, SDL_PIXELFORMAT_RGBA32);
  if(!surface){
    SDL_Log("Failed to create dummy SDL_Surface: %s", SDL_GetError());
    return null;
  }

  if(SDL_MUSTLOCK(surface)) SDL_LockSurface(surface);
  auto whitePixel = SDL_MapRGBA(SDL_GetPixelFormatDetails(surface.format), null, 255, 255, 255, 255);
  memcpy(surface.pixels, &whitePixel, SDL_GetPixelFormatDetails(surface.format).bytes_per_pixel);
  if(SDL_MUSTLOCK(surface)) SDL_UnlockSurface(surface);
  return surface;
}

int isSupported(ref App app, VkFormat requested){
  int s = -1;
  foreach(i, fmt; app.surfaceformats) { if(fmt.format == requested) s = cast(int)(i); }
  return(s);
}

void queryPresentFormats(ref App app) {
  uint formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(app.physicalDevice, app.surface, &app.camera.capabilities));  // Capabilities
  app.camera.isDirty = true;
  if(app.verbose) SDL_Log("Capablities: ImageCount: %d - %d", app.camera.capabilities.minImageCount, app.camera.capabilities.maxImageCount);

  // Surface formats
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, null));
  app.surfaceformats.length = formatCount;
  enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(app.physicalDevice, app.surface, &formatCount, &app.surfaceformats[0]));

  if (app.verbose) {
    SDL_Log("[SurfaceCapabilities] formatCount: %d", formatCount);
    foreach(fmt; app.surfaceformats){ fmt.printSurfaceFormat(); }
  }
}

bool supportsColorFormat(ref App app, VkFormat requested = VK_FORMAT_R16G16B16A16_SFLOAT) {
  VkFormatProperties formatProperties;
  vkGetPhysicalDeviceFormatProperties(app.physicalDevice, requested, &formatProperties);
  if (formatProperties.optimalTilingFeatures & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT &&
      formatProperties.optimalTilingFeatures & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT) {
    return(true);
  }
  return(false);
}

VkSurfaceFormatKHR getBestColorFormat(ref App app){
  auto ordering = [VK_FORMAT_R32G32B32A32_SFLOAT, VK_FORMAT_R16G16B16A16_SFLOAT, VK_FORMAT_R8G8B8A8_SRGB, VK_FORMAT_R8G8B8A8_UNORM];
  version(Android){
    ordering = [VK_FORMAT_R5G6B5_UNORM_PACK16, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_R16G16B16A16_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT];
  }
  foreach(format; ordering){ if(app.supportsColorFormat(format)){
    return(app.offscreen = VkSurfaceFormatKHR(format, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR));
  } }
  assert(0, "No suitable format found");
}
