import includes;
import application : App;
import physicaldevice : pickPhysicalDevice;
import instance : createInstance, addExtension, loadExtensionProperties, isExtensionAvailable;
import vkdebug : enforceVK, createDebugCallback;

void setupVulkan(ref App app) {
  app.loadExtensionProperties();
  app.createInstance();
  app.createDebugCallback();
  app.pickPhysicalDevice();

  //  Select graphics queue family
  app.queueFamily = ImGui_ImplVulkanH_SelectQueueFamilyIndex(app.physicalDevice);

  uint32_t device_extensions_count = 1;
  const(char)*[] device_extensions = ["VK_KHR_swapchain"];

  // Create Logical Device (with 1 queue)
  float[] queue_priority = [1.0f];
  VkDeviceQueueCreateInfo[1] queue_info;
  queue_info[0].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  queue_info[0].queueFamilyIndex = app.queueFamily;
  queue_info[0].queueCount = 1;
  queue_info[0].pQueuePriorities = &queue_priority[0];

  VkDeviceCreateInfo createDevice = {
    sType : VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    queueCreateInfoCount : queue_info.sizeof / queue_info[0].sizeof,
    pQueueCreateInfos : &queue_info[0],
    enabledExtensionCount : device_extensions_count,
    ppEnabledExtensionNames : &device_extensions[0],
  };
  vkCreateDevice(app.physicalDevice, &createDevice, app.allocator, &app.dev);

  vkGetDeviceQueue(app.dev, app.queueFamily, 0, &app.queue);

  // Create Descriptor Pool
  VkDescriptorPoolSize[] pool_sizes = [ { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE } ];
  uint maxSets = 0;
  for(int i = 0; i < pool_sizes.length; i++){
      VkDescriptorPoolSize pool_size = pool_sizes[i];
      maxSets += pool_size.descriptorCount;
  }

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : maxSets,
    poolSizeCount : cast(uint32_t)pool_sizes.length,
    pPoolSizes : &pool_sizes[0]
  };
  vkCreateDescriptorPool(app.dev, &createPool, app.allocator, &app.descriptorPool);
}
