import includes;
import application : App;
import vkdebug : enforceVK;

// Supporting structs
struct VkQueueFamilyIndices {
  uint graphicsFamily;
  uint presentFamily;
};

void selectGraphicsQueueFamilyIndex(ref App app) {
  uint numQueues;
  app.familyIndices.graphicsFamily = uint.max;

  vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice, &numQueues, null);
  SDL_Log("Number of queues on selected device(%d): %d", app.selected, numQueues);
  auto queueFamilyProperties = new VkQueueFamilyProperties[](numQueues);
  vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice, &numQueues, queueFamilyProperties.ptr);
  foreach (i, fproperties; queueFamilyProperties) {
    if (fproperties.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
      VkBool32 presentSupport = false;
      SDL_Log("VK_QUEUE_GRAPHICS_BIT: %d", i);
      enforceVK(vkGetPhysicalDeviceSurfaceSupportKHR(app.physicalDevice, cast(uint)i, app.surface, &presentSupport));
      if (presentSupport) { app.familyIndices.presentFamily = cast(uint)i; }
      if (app.familyIndices.graphicsFamily == uint32_t.max){ app.familyIndices.graphicsFamily = cast(uint)i; }
    }
  }
  SDL_Log(" - app.familyIndices.presentFamily: %d", app.familyIndices.presentFamily);
  SDL_Log(" - app.familyIndices.graphicsFamily: %d", app.familyIndices.graphicsFamily);
}


// Create the logical device, and load the device level functions, to supplement the local and global level functions
void createLogicalDevice(ref App app){
  app.selectGraphicsQueueFamilyIndex();
  float[1] queuePriorities = [ 0.0f ];
  VkDeviceQueueCreateInfo queueCreateInfo = {
    sType : VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    queueCount : 1,
    pQueuePriorities : queuePriorities.ptr,
    queueFamilyIndex : app.familyIndices.graphicsFamily,
  };

  const(char)*[] deviceExtensions = [ "VK_KHR_swapchain" ];

  VkPhysicalDeviceFeatures supportedFeatures = {};
  vkGetPhysicalDeviceFeatures(app.physicalDevice, &supportedFeatures);
  SDL_Log("Physical device support (fillModeNonSolid): %d", supportedFeatures.fillModeNonSolid);
  SDL_Log("Physical device support (Anisotropy): %d", supportedFeatures.samplerAnisotropy);
  SDL_Log("Physical device support (GeometryShader): %d", supportedFeatures.geometryShader);
  SDL_Log("Physical device support (TessellationShader): %d", supportedFeatures.tessellationShader);

  VkPhysicalDeviceFeatures deviceFeatures = {
    fillModeNonSolid: ((supportedFeatures.fillModeNonSolid) ? VK_TRUE : VK_FALSE),
    samplerAnisotropy: ((supportedFeatures.samplerAnisotropy) ? VK_TRUE : VK_FALSE),
    geometryShader: ((supportedFeatures.geometryShader) ? VK_TRUE : VK_FALSE),
    tessellationShader: ((supportedFeatures.tessellationShader) ? VK_TRUE : VK_FALSE)
  };

  VkDeviceCreateInfo deviceCreateInfo = {
    sType : VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    queueCreateInfoCount : 1,
    pQueueCreateInfos : &queueCreateInfo,
    enabledExtensionCount : cast(uint)deviceExtensions.length,
    ppEnabledExtensionNames : &deviceExtensions[0],
    pEnabledFeatures: &deviceFeatures
  };

  enforceVK(vkCreateDevice(app.physicalDevice, &deviceCreateInfo, null, &app.dev));
  SDL_Log("Logical device %p created", app.dev);
  vkGetDeviceQueue(app.dev, app.familyIndices.graphicsFamily, 0, &app.gfxQueue);
  SDL_Log("Logical device graphics queue obtained");
//  vkGetDeviceQueue(app.dev, app.familyIndices.presentFamily, 0, &app.presentQueue);
//  SDL_Log("Logical device present queue obtained");
}

