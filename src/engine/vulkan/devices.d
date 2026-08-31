/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import extensions : queryDeviceExtensionProperties, has;
import queue : findDedicatedQueues, setupQueues;
import validation : nameVulkanObject;
import vulkan : querySupportedFeatures;
import vram : memoryReportCallback, hasMemoryBudget, hasMemoryCallback;

// Creates a physicalDevice & associated Queue
void pickPhysicalDevice(ref App app, uint device = 0){
  app.queryPhysicalDevices();  // Query Physical Devices and pick 0
  app.selectedDevice = device;
  auto extension = app.queryDeviceExtensionProperties();

  if(extension.has("VK_KHR_swapchain")){ app.deviceExtensions ~= "VK_KHR_swapchain"; }
  if(extension.has("VK_EXT_memory_budget")){ app.deviceExtensions ~= "VK_EXT_memory_budget"; }
  if(extension.has("VK_EXT_device_memory_report")){ app.deviceExtensions ~= "VK_EXT_device_memory_report"; }
  if(extension.has("VK_KHR_maintenance3")){ app.deviceExtensions ~= "VK_KHR_maintenance3"; }
  if(extension.has("VK_EXT_descriptor_indexing")){ app.deviceExtensions ~= "VK_EXT_descriptor_indexing"; }

  app.printQueues();
}

/** Get the number of Multisample anti-aliasing (MSAA) samples */
VkSampleCountFlagBits getMSAASamples(ref App app) {
  version (Android) { return VK_SAMPLE_COUNT_1_BIT; }
  VkSampleCountFlags counts = app.properties.limits.framebufferColorSampleCounts & app.properties.limits.framebufferDepthSampleCounts;
  if (counts & VK_SAMPLE_COUNT_64_BIT) { return VK_SAMPLE_COUNT_64_BIT; }
  if (counts & VK_SAMPLE_COUNT_32_BIT) { return VK_SAMPLE_COUNT_32_BIT; }
  if (counts & VK_SAMPLE_COUNT_16_BIT) { return VK_SAMPLE_COUNT_16_BIT; }
  if (counts & VK_SAMPLE_COUNT_8_BIT)  { return VK_SAMPLE_COUNT_8_BIT;  }
  if (counts & VK_SAMPLE_COUNT_4_BIT)  { return VK_SAMPLE_COUNT_4_BIT;  }
  if (counts & VK_SAMPLE_COUNT_2_BIT)  { return VK_SAMPLE_COUNT_2_BIT;  }
  return VK_SAMPLE_COUNT_1_BIT;
}

/** Create Logical Device (with 1 queue) */
void createLogicalDevice(ref App app, uint device = 0, uint queueCount = 2){
  app.pickPhysicalDevice(device);
  app.querySupportedFeatures(app.physicalDevice);

  VkPhysicalDeviceDeviceMemoryReportFeaturesEXT memReportFeatures = {
    sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DEVICE_MEMORY_REPORT_FEATURES_EXT,
    deviceMemoryReport: VK_TRUE,
  };

  VkDeviceDeviceMemoryReportCreateInfoEXT memReportCreateInfo = {
    sType: VK_STRUCTURE_TYPE_DEVICE_DEVICE_MEMORY_REPORT_CREATE_INFO_EXT,
    flags: 0, pfnUserCallback: &memoryReportCallback, pUserData: &app,
  };

  VkPhysicalDeviceVulkan12Features features = { 
    sType : VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
    descriptorIndexing : VK_TRUE,
    runtimeDescriptorArray : VK_TRUE,
    shaderSampledImageArrayNonUniformIndexing : VK_TRUE,
    shaderStorageBufferArrayNonUniformIndexing : VK_TRUE,
    descriptorBindingPartiallyBound : VK_TRUE,
  };

  if(!app.hasMemoryBudget() && app.hasMemoryCallback()) {
    memReportFeatures.pNext = &memReportCreateInfo;
    features.pNext = &memReportFeatures;
  }

  VkPhysicalDeviceFeatures deviceFeatures = { robustBufferAccess: VK_TRUE,
                                              samplerAnisotropy: VK_TRUE,
                                              fragmentStoresAndAtomics: VK_TRUE,
                                              independentBlend: VK_TRUE};

  QueueSetup qs = app.findDedicatedQueues();
  VkDeviceCreateInfo createDevice = {
    sType : VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    queueCreateInfoCount : cast(uint)qs.createInfos.length, pQueueCreateInfos : &qs.createInfos[0],
    enabledExtensionCount : cast(uint)app.deviceExtensions.length, ppEnabledExtensionNames : &app.deviceExtensions[0],
    pEnabledFeatures : &deviceFeatures,
    pNext : &features
  };
  enforceVK(vkCreateDevice(app.physicalDevice, &createDevice, app.allocator, &app.device));

  VmaVulkanFunctions vkFuncs = { vkGetInstanceProcAddr: &vkGetInstanceProcAddr, vkGetDeviceProcAddr: &vkGetDeviceProcAddr };

  VmaAllocatorCreateInfo vmaInfo = {
    physicalDevice: app.physicalDevice, device: app.device, instance: app.instance,
    vulkanApiVersion: app.applicationInfo.apiVersion, pVulkanFunctions: &vkFuncs
  };
  enforceVK(vmaCreateAllocator(&vmaInfo, &app.vma));

  app.mainDeletionQueue.add((){ if(app.verbose) SDL_Log("Destroy Device: %p", app.device);
    vmaDestroyAllocator(app.vma);
    vkDestroyDevice(app.device, app.allocator); 
  });

  if(app.verbose) SDL_Log("vkCreateDevice[extensions:%d]: %p", app.deviceExtensions.length, app.device);

  app.setupQueues(qs);
  if(app.verbose) SDL_Log("Queue: gfx=%d compute=%d transfer=%d", app.queues.graphics.family, app.queues.compute.family, app.queues.transfer.family);
}

/** List / Print information about a physical device */
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

/** Query available physical devices */
void queryPhysicalDevices(ref App app) {
  uint nPhysDevices = 0;
  vkEnumeratePhysicalDevices(app.instance, &nPhysDevices, null);
  if(app.verbose) SDL_Log("Number of physical vulkan devices found: %d", nPhysDevices);
  if(nPhysDevices == 0) {
    stop("No Vulkan Device", "No Vulkan-capable GPU found, a graphics card and drivers that support Vulkan 1.2 or newer is required.");
  }
  app.physicalDevices.length = nPhysDevices;
  vkEnumeratePhysicalDevices(app.instance, &nPhysDevices, &app.physicalDevices[0]);
  if(app.verbose) foreach(i, physicalDevice; app.physicalDevices) { physicalDevice.list(i); }
}

/** Print (gfx) queue information */
void printQueues(ref App app){
  uint32_t nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice, &nQueue, null);
  VkQueueFamilyProperties[] queueProperties;
  queueProperties.length = nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice, &nQueue, &queueProperties[0]);
  foreach(i, queueProperty; queueProperties) {
    string[] capabilities;
    if(queueProperty.queueFlags & VK_QUEUE_GRAPHICS_BIT) capabilities ~= "Graphics";
    if(queueProperty.queueFlags & VK_QUEUE_COMPUTE_BIT) capabilities ~= "Compute";
    if(queueProperty.queueFlags & VK_QUEUE_TRANSFER_BIT) capabilities ~= "Transfer";
    SDL_Log(cstr("Queue[%d] size: %d: %s", i, queueProperty.queueCount, capabilities));
  }
}

/** Integration: full headless Vulkan bring-up (instance -> device -> VMA -> buffer), no window/surface */
unittest {
  import buffer : createBuffer;
  import extensions : queryInstanceExtensionProperties;
  import instance : createInstance;

  App app;
  app.enableValidation = false;                     // CI ICD (lavapipe) has no validation layer

  // --- Instance: always testable, even with no physical device ---
  app.createInstance();
  assert(app.instance !is null, "vkCreateInstance produced a null instance");

  auto exts = app.queryInstanceExtensionProperties();
  assert(exts.length > 0, "no instance extensions reported");
  assert(exts.has("VK_KHR_surface"), "VK_KHR_surface should always be present");
  assert(!exts.has("VK_KHR_does_not_exist"), "phantom extension reported present");

  // --- Device: skip gracefully if the runner has no usable Vulkan device ---
  app.createLogicalDevice();                         // pickPhysicalDevice + queues + VMA
  if(app.device is null) {                           // no ICD/device here: instance coverage still ran
    vkDestroyInstance(app.instance, app.allocator);
    return;
  }
  assert(app.physicalDevices.length >= 1, "no physical device enumerated");
  assert(app.vma !is null, "VMA allocator not created");
  assert(app.queues.graphics.family != uint.max, "graphics queue family unresolved");
  assert(app.properties().limits.maxImageDimension2D >= 4096, "implausible device limits");

  // --- Buffer: VMA allocates host-visible memory that maps and round-trips ---
  VkBuffer buf; VmaAllocation alloc;
  app.createBuffer(&buf, &alloc, 4096, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  assert(buf != VK_NULL_HANDLE && alloc !is null, "createBuffer failed");

  void* mapped;
  enforceVK(vmaMapMemory(app.vma, alloc, &mapped));
  (cast(uint*)mapped)[0] = 0xDEADBEEF;
  assert((cast(uint*)mapped)[0] == 0xDEADBEEF, "mapped memory did not retain written value");
  vmaUnmapMemory(app.vma, alloc);

  // --- Teardown in reverse creation order ---
  vmaDestroyBuffer(app.vma, buf, alloc);
  vmaDestroyAllocator(app.vma);
  vkDestroyDevice(app.device, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);
}
