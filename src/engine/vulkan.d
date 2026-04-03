/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : saveSettings;
import geometry : cleanup;

struct SupportedFeatures {
 VkPhysicalDeviceFeatures base;
 VkPhysicalDeviceVulkan12Features vk12;
 VkPhysicalDevice16BitStorageFeatures vk16;
}

/** query Supported Vulkan Features & enforce minimal feature set required
 */
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
    ImGui_ImplSDL3_Shutdown();
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