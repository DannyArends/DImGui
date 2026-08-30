/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : saveSettings;
import threading : stopWorkers;

struct SupportedFeatures {
 VkPhysicalDeviceFeatures base;
 VkPhysicalDeviceVulkan12Features vk12;
 VkPhysicalDevice16BitStorageFeatures vk16;
}

/** Human-readable VkResult name */
const(char)* vkResultStr(VkResult r) @nogc nothrow {
  switch(r){
    case VK_ERROR_OUT_OF_HOST_MEMORY:      return("out of host memory");
    case VK_ERROR_OUT_OF_DEVICE_MEMORY:    return("out of device (GPU) memory");
    case VK_ERROR_INITIALIZATION_FAILED:   return("initialisation failed");
    case VK_ERROR_DEVICE_LOST:             return("device lost");
    case VK_ERROR_LAYER_NOT_PRESENT:       return("a requested layer is not present");
    case VK_ERROR_EXTENSION_NOT_PRESENT:   return("a requested extension is not present");
    case VK_ERROR_FEATURE_NOT_PRESENT:     return("a required GPU feature is not present");
    case VK_ERROR_INCOMPATIBLE_DRIVER:     return("no compatible Vulkan driver (update GPU drivers)");
    case VK_ERROR_FORMAT_NOT_SUPPORTED:    return("required format not supported");
    case VK_ERROR_SURFACE_LOST_KHR:        return("window surface lost");
    case VK_ERROR_OUT_OF_DATE_KHR:         return("swapchain out of date");
    default:                               return("unknown Vulkan error");
  }
}

/** Show a fatal error dialog and exit cleanly (no silent abort) */
extern(C) @nogc void fatalError(const(char)* title, const(char)* message) nothrow {
  SDL_Log("[FATAL] %s: %s", title, message);
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, title, message, null);
  exit(1);
}

/** Check result of Vulkan call and print if an error occured */
extern(C) @nogc void enforceVK(VkResult err) nothrow {
  if (err == VK_SUCCESS) return;
  SDL_Log("[enforceVK] VkResult = %d (%s)", err, vkResultStr(err));
  if (err < 0) {
    char[256] buf;
    SDL_snprintf(buf.ptr, buf.length, "Error: %s.\n\nUpdate your GPU drivers and ensure Vulkan 1.2+ is supported.", vkResultStr(err));
    fatalError("Vulkan Error", buf.ptr);
  }
}

/** query Supported Vulkan Features & enforce minimal feature set required */
void querySupportedFeatures(ref App app, VkPhysicalDevice physicalDevice) {
  app.supported.vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
  app.supported.vk16.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES;
  app.supported.vk12.pNext = &app.supported.vk16;

  VkPhysicalDeviceFeatures2 f2 = {
    sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    pNext: &app.supported.vk12
  };
  vkGetPhysicalDeviceFeatures2(physicalDevice, &f2);
  app.supported.base = f2.features;

  /// Minimal features
  if(!app.supported.base.robustBufferAccess) assert(0, "Vulkan 1.0 feature not supported: robustBufferAccess");
  if(!app.supported.vk12.descriptorIndexing) assert(0, "Vulkan 1.2 feature not supported: descriptorIndexing");
  if(!app.supported.vk12.runtimeDescriptorArray) assert(0, "Vulkan 1.2 feature not supported: runtimeDescriptorArray");
  if(!app.supported.vk12.shaderSampledImageArrayNonUniformIndexing) assert(0, "Vulkan 1.2 feature not supported: shaderSampledImageArrayNonUniformIndexing");
  if(!app.supported.vk12.shaderStorageBufferArrayNonUniformIndexing) assert(0, "Vulkan 1.2 feature not supported: shaderStorageBufferArrayNonUniformIndexing");
  if(!app.supported.vk12.descriptorBindingPartiallyBound) assert(0, "Vulkan 1.2 feature not supported: descriptorBindingPartiallyBound");
}

/** Shutdown ImGui and deAllocate all vulkan related objects in existance */
void cleanup(ref App app) {
  SDL_Log("Wait on device idle & swapchain deletion queue");
  enforceVK(vkDeviceWaitIdle(app.device));
  SDL_Log("Delete bufferDeletionQueue associated resources");
  app.bufferDeletionQueue.flush(true);
  SDL_Log("Delete SwapChain associated resources");
  app.swapDeletionQueue.flush();

  SDL_Log("Free any pending texture buffers (GPU is idle, all fences signaled)");
  foreach(ref p; app.textures.pending) {
    import buffer : cleanup;
    app.cleanup(p.staging);
    SDL_DestroySurface(p.texture.surface);
    vkDestroyFence(app.device, p.cmdBuffer.fence, app.allocator);
    vkFreeCommandBuffers(app.device, p.cmdBuffer.pool, 1, &p.cmdBuffer.commands);
  }
  app.textures.pending = [];

  if (app.isImGuiInitialized) {
    SDL_Log("Save ImGui Settings");
    saveSettings();

    SDL_Log("Shutdown ImGui");
    ImGui_ImplVulkan_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    igDestroyContext(null);
  }
  SDL_Log("Direct cleanup all Geometry objects");
  foreach(ref object; app.objects) {
    import geometry : cleanup;
    app.cleanup(object);
  }

  SDL_Log("Flush the main deletion queue, and delete permanent Vulkan resources");
  app.mainDeletionQueue.flush();

  SDL_Log("Joining worker threads");
  app.stopWorkers();
  thread_joinAll();

  SDL_Log("Destroying active tracks and audio.mixer");
  foreach(track; app.audio.activeTracks) { MIX_DestroyTrack(track); }
  app.audio.activeTracks = [];
  if(app.audio.mixer) MIX_DestroyMixer(app.audio.mixer);

  SDL_Log("Destroying Window & Quit SDL");
  SDL_DestroyWindow(app);
  SDL_Quit();
}
