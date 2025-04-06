import engine;

void list(VkPhysicalDevice physicalDevice, size_t i) {
  VkPhysicalDeviceProperties properties;
  vkGetPhysicalDeviceProperties(physicalDevice, &properties);
  SDL_Log("-Physical Device[%d]: %s", i, properties.deviceName.ptr);
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

VkPhysicalDevice[] queryPhysicalDevices(ref App app) {
  uint nPhysDevices = 0;
  VkPhysicalDevice[] physicalDevices;
  vkEnumeratePhysicalDevices(app.instance, &nPhysDevices, null);
  SDL_Log("Number of physical vulkan devices found: %d", nPhysDevices);
  physicalDevices.length = nPhysDevices;
  vkEnumeratePhysicalDevices(app.instance, &nPhysDevices, &physicalDevices[0]);
  if(app.verbose) foreach(i, physicalDevice; physicalDevices) { physicalDevice.list(i); }
  return(physicalDevices);
}

// Load Device Extensions Properties
VkExtensionProperties[] queryDeviceExtensionProperties(ref App app, const(char)* layer = null) {
  if(app.verbose) SDL_Log("queryInstanceExtensionProperties");
  uint nProperties;
  VkExtensionProperties[] properties;

  vkEnumerateDeviceExtensionProperties(app.physicalDevice, null, &nProperties, null);
  if(nProperties == 0) return properties;
  properties.length = nProperties;
  enforceVK(vkEnumerateDeviceExtensionProperties(app.physicalDevice, null, &nProperties, &properties[0]));
  SDL_Log("Found %d device extensions", properties.length);
  if(app.verbose) foreach(i, property; properties) { SDL_Log("-Extension[%d] %s", i, property.extensionName.ptr); }
  return(properties);
}

uint selectQueueFamily(VkPhysicalDevice physicalDevice){
  uint32_t nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &nQueue, null);
  VkQueueFamilyProperties[] queueProperties;
  queueProperties.length = nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &nQueue, &queueProperties[0]);
  foreach(i, queueProperty; queueProperties) {
    if (queueProperty.queueFlags & VK_QUEUE_GRAPHICS_BIT) return cast(uint)i;
  }
  assert(0);
}
