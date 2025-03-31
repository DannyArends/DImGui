import includes;

import application : App;

void pickPhysicalDevice(ref App app, uint select = 0) {
  uint pDevicetype = 0;
  vkEnumeratePhysicalDevices(app.instance, &app.nPhysDevices, null);
  SDL_Log("Number of physical vulkan devices found: %d", app.nPhysDevices);
  app.physicalDevices.length = app.nPhysDevices;
  vkEnumeratePhysicalDevices(app.instance, &app.nPhysDevices, &app.physicalDevices[0]);
  if(select > app.nPhysDevices) select = 0;

  foreach(i, physDevice; app.physicalDevices) {
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(physDevice, &properties);
    SDL_Log("-Physical device %d: %s", i, properties.deviceName.ptr);
    SDL_Log("|- API Version: %d.%d.%d", VK_API_VERSION_MAJOR(properties.apiVersion),
                                        VK_API_VERSION_MINOR(properties.apiVersion),
                                        VK_API_VERSION_PATCH(properties.apiVersion));
    SDL_Log("|- Image sizes: (1D/2D/3D) %d %d %d", properties.limits.maxImageDimension1D,
                                                   properties.limits.maxImageDimension2D,
                                                   properties.limits.maxImageDimension3D);
    SDL_Log("|- Max PushConstantSize: %d", properties.limits.maxPushConstantsSize);
    SDL_Log("|- Max MemoryAllocationCount: %d", properties.limits.maxMemoryAllocationCount);
    SDL_Log("|- Max ImageArrayLayers: %d", properties.limits.maxImageArrayLayers);
    SDL_Log("|- Max SamplerAllocationCount: %d", properties.limits.maxSamplerAllocationCount);
    SDL_Log("|- Device type: %d", properties.deviceType);
    if(i > select && properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU && pDevicetype == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
      SDL_Log("|- Switching to from integrated to discrete GPU device: %d", (i+1));
      select = cast(uint)i;
    }
    pDevicetype = properties.deviceType;
  }
  app.selected = select;
  SDL_Log("Physical device %d from %d selected", (app.selected + 1), app.physicalDevices.length);
}

