/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import extensions : queryDeviceExtensionProperties, has;
import validation : nameVulkanObject;

// Creates a physicalDevice & associated Queue
void pickPhysicalDevice(ref App app, uint device = 0){
  app.queryPhysicalDevices();  // Query Physical Devices and pick 0
  app.selectedDevice = device;
  auto extension = app.queryDeviceExtensionProperties();

  if(extension.has("VK_KHR_swapchain")){ app.deviceExtensions ~= "VK_KHR_swapchain"; }
  if(extension.has("VK_KHR_maintenance3")){ app.deviceExtensions ~= "VK_KHR_maintenance3"; }
  if(extension.has("VK_EXT_descriptor_indexing")){ app.deviceExtensions ~= "VK_EXT_descriptor_indexing"; }

  app.queueFamily = selectQueueFamily(app.physicalDevice());
}

VkSampleCountFlagBits getMSAASamples(ref App app) {
  version (Android) { return VK_SAMPLE_COUNT_4_BIT; }
  VkSampleCountFlags counts = app.properties.limits.framebufferColorSampleCounts & app.properties.limits.framebufferDepthSampleCounts;
  if (counts & VK_SAMPLE_COUNT_64_BIT) { return VK_SAMPLE_COUNT_64_BIT; }
  if (counts & VK_SAMPLE_COUNT_32_BIT) { return VK_SAMPLE_COUNT_32_BIT; }
  if (counts & VK_SAMPLE_COUNT_16_BIT) { return VK_SAMPLE_COUNT_16_BIT; }
  if (counts & VK_SAMPLE_COUNT_8_BIT)  { return VK_SAMPLE_COUNT_8_BIT;  }
  if (counts & VK_SAMPLE_COUNT_4_BIT)  { return VK_SAMPLE_COUNT_4_BIT;  }
  if (counts & VK_SAMPLE_COUNT_2_BIT)  { return VK_SAMPLE_COUNT_2_BIT;  }
  return VK_SAMPLE_COUNT_1_BIT;
}

// Create Logical Device (with 1 queue)
void createLogicalDevice(ref App app, uint device = 0){
  app.pickPhysicalDevice(device);

  float[] queuePriority = [1.0f];
  VkDeviceQueueCreateInfo[] createQueue = [{
    sType : VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    queueFamilyIndex : app.queueFamily,
    queueCount : 2, // transfer and render queue
    pQueuePriorities : &queuePriority[0]
  }];

  VkPhysicalDeviceVulkan12Features features = { 
    sType : VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
    descriptorIndexing : VK_TRUE,
    runtimeDescriptorArray : VK_TRUE,
    shaderSampledImageArrayNonUniformIndexing : VK_TRUE,
    shaderStorageBufferArrayNonUniformIndexing : VK_TRUE,
    pNext : null
  };

  VkDeviceCreateInfo createDevice = {
    sType : VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    queueCreateInfoCount : cast(uint)createQueue.length,
    pQueueCreateInfos : &createQueue[0],
    enabledExtensionCount : cast(uint)app.deviceExtensions.length,
    ppEnabledExtensionNames : &app.deviceExtensions[0],
    pNext : &features
  };
  enforceVK(vkCreateDevice(app.physicalDevice, &createDevice, app.allocator, &app.device));

  app.mainDeletionQueue.add((){ if(app.verbose) SDL_Log("Destroy Device: %p", app.device);
    vkDestroyDevice(app.device, app.allocator); 
  });

  if(app.verbose) SDL_Log("vkCreateDevice[extensions:%d]: %p", app.deviceExtensions.length, app.device);

  // Get the Queue from the queueFamily
  vkGetDeviceQueue(app.device, app.queueFamily, 0, &app.queue);
  vkGetDeviceQueue(app.device, app.queueFamily, 1, &app.transfer);

  app.nameVulkanObject(app.device, toStringz("[DEVICE]"), VK_OBJECT_TYPE_DEVICE);
  app.nameVulkanObject(app.physicalDevice, toStringz(format("[PHYSICAL DEVICE] %s", fromStringz(app.properties.deviceName.ptr))), VK_OBJECT_TYPE_PHYSICAL_DEVICE);
  app.nameVulkanObject(app.instance, toStringz("[INSTANCE]"), VK_OBJECT_TYPE_INSTANCE);
  app.nameVulkanObject(app.queue, toStringz("[QUEUE] Render"), VK_OBJECT_TYPE_QUEUE);
  app.nameVulkanObject(app.transfer, toStringz("[QUEUE] Transfer"), VK_OBJECT_TYPE_QUEUE);

  if(app.verbose) SDL_Log("vkGetDeviceQueue[family:%d] queue: %p, transfer: %p", app.queueFamily, app.queue, app.transfer);
}

void list(VkPhysicalDevice physicalDevice, size_t i) {
  VkPhysicalDeviceProperties properties;
  vkGetPhysicalDeviceProperties(physicalDevice, &properties);
  SDL_Log("-Physical Device[%d]: %p %s", i, physicalDevice, properties.deviceName.ptr);
  SDL_Log("|- API Version: %d.%d.%d", VK_API_VERSION_MAJOR(properties.apiVersion),
                                      VK_API_VERSION_MINOR(properties.apiVersion),
                                      VK_API_VERSION_PATCH(properties.apiVersion));
  SDL_Log("|- Image sizes: (1D/2D/3D) %d %d %d", properties.limits.maxImageDimension1D,
                                                 properties.limits.maxImageDimension2D,
                                                 properties.limits.maxImageDimension3D);
  SDL_Log("|- Max PushConstantSize: %d", properties.limits.maxPushConstantsSize);
  SDL_Log("|- Max ImageArrayLayers: %d", properties.limits.maxImageArrayLayers);
  SDL_Log("|- Max SamplerAllocationCount: %d", properties.limits.maxSamplerAllocationCount);
  SDL_Log("|- Device type: %d", properties.deviceType);
}

void queryPhysicalDevices(ref App app) {
  uint nPhysDevices = 0;
  vkEnumeratePhysicalDevices(app.instance, &nPhysDevices, null);
  if(app.verbose) SDL_Log("Number of physical vulkan devices found: %d", nPhysDevices);
  app.physicalDevices.length = nPhysDevices;
  vkEnumeratePhysicalDevices(app.instance, &nPhysDevices, &app.physicalDevices[0]);
  if(app.verbose) foreach(i, physicalDevice; app.physicalDevices) { physicalDevice.list(i); }
}

uint selectQueueFamily(VkPhysicalDevice physicalDevice) {
  uint32_t nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &nQueue, null);
  VkQueueFamilyProperties[] queueProperties;
  queueProperties.length = nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &nQueue, &queueProperties[0]);
  foreach(i, queueProperty; queueProperties) {
    if(queueProperty.queueFlags & VK_QUEUE_GRAPHICS_BIT) SDL_Log("[%d] Graphic Queue, size: %d", i, queueProperty.queueCount);
    if(queueProperty.queueFlags & VK_QUEUE_COMPUTE_BIT) SDL_Log("[%d] Compute Queue, size: %d", i, queueProperty.queueCount);
    if(queueProperty.queueFlags & VK_QUEUE_TRANSFER_BIT) SDL_Log("[%d] Transfer Queue, size: %d", i, queueProperty.queueCount);
    if((queueProperty.queueFlags & VK_QUEUE_GRAPHICS_BIT) && (queueProperty.queueFlags & VK_QUEUE_COMPUTE_BIT)) return cast(uint)i;
  }
  assert(0);
}

