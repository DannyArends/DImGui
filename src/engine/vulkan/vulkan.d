/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : cleanup;
import imgui : saveSettings;
import threading : stopWorkers;

struct SupportedFeatures {
 VkPhysicalDeviceFeatures base;
 VkPhysicalDeviceVulkan12Features vk12;
 VkPhysicalDevice16BitStorageFeatures vk16;
}

/** query Supported Vulkan Features & enforce minimal feature set required */
void querySupportedFeatures(ref App app, VkPhysicalDevice physicalDevice) {
  app.supported.vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
  app.supported.vk16.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES;

  // Vulkan 1.1 drivers (Quest 1 / Adreno 540) don't populate the vk12 aggregate;
  // query descriptor indexing through the EXT struct, which they do fill in.
  VkPhysicalDeviceDescriptorIndexingFeaturesEXT di = {
    sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT };
  app.supported.vk12.pNext = &app.supported.vk16;
  app.supported.vk16.pNext = &di;

  VkPhysicalDeviceFeatures2 f2 = {
    sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    pNext: &app.supported.vk12
  };
  vkGetPhysicalDeviceFeatures2(physicalDevice, &f2);
  app.supported.base = f2.features;

  // Fold EXT results into vk12 so downstream code sees consistent flags on 1.1.
  if(!app.supported.vk12.runtimeDescriptorArray) app.supported.vk12.runtimeDescriptorArray = di.runtimeDescriptorArray;
  if(!app.supported.vk12.shaderSampledImageArrayNonUniformIndexing) app.supported.vk12.shaderSampledImageArrayNonUniformIndexing = di.shaderSampledImageArrayNonUniformIndexing;
  if(!app.supported.vk12.shaderStorageBufferArrayNonUniformIndexing) app.supported.vk12.shaderStorageBufferArrayNonUniformIndexing = di.shaderStorageBufferArrayNonUniformIndexing;
  if(!app.supported.vk12.descriptorBindingPartiallyBound) app.supported.vk12.descriptorBindingPartiallyBound = di.descriptorBindingPartiallyBound;
  if(!app.supported.vk12.descriptorIndexing) app.supported.vk12.descriptorIndexing = di.runtimeDescriptorArray; // EXT has no aggregate flag; proxy it

  // Report (don't trap) so an unsupported device names what it lacks.
  void req(VkBool32 ok, string f) { if(!ok) SDL_Log("Missing required Vulkan feature: %s", f.ptr); }
  req(app.supported.base.robustBufferAccess, "robustBufferAccess");
  req(app.supported.vk12.runtimeDescriptorArray, "runtimeDescriptorArray");
  req(app.supported.vk12.shaderSampledImageArrayNonUniformIndexing, "shaderSampledImageArrayNonUniformIndexing");
  req(app.supported.vk12.shaderStorageBufferArrayNonUniformIndexing, "shaderStorageBufferArrayNonUniformIndexing");
  req(app.supported.vk12.descriptorBindingPartiallyBound, "descriptorBindingPartiallyBound");
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
  foreach(ref object; app.objects) { app.cleanup(object); }

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
