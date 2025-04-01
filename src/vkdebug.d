import includes;
import std.string : toStringz;
import application : App;

PFN_vkCreateDebugReportCallbackEXT  vkDebugCallback;
PFN_vkDestroyDebugReportCallbackEXT vkDestroyDebugCallback;

extern(C) void enforceVK(VkResult err) {
  if (err == VK_SUCCESS) return;
  SDL_Log("[vulkan] Error: VkResult = %d\n", err);
  if (err < 0) abort();
}

extern(C) uint debugCallback(VkDebugReportFlagsEXT flags, VkDebugReportObjectTypeEXT objectType, uint64_t object, 
                            size_t location, int32_t messageCode, const char* pLayerPrefix, const char* pMessage, void* pUserData) {
    SDL_Log("[vulkan] Debug report from ObjectType: %i\nMessage: %s\n\n", objectType, pMessage);
    return VK_FALSE;
}

bool checkValidationLayerSupport(ref App app, const(char*) layerName) {
  uint32_t nLayers;
  vkEnumerateInstanceLayerProperties(&nLayers, null);
  SDL_Log("checkValidationLayerSupport: %s, layerCount: %d", layerName, nLayers);
  if(nLayers == 0) return(false);

  VkLayerProperties[] availableLayers;
  availableLayers.length = nLayers;
  vkEnumerateInstanceLayerProperties(&nLayers, &availableLayers[0]);
  bool layerFound = false;
  foreach(layerProperties; availableLayers) {
    if (strcmp(layerName, layerProperties.layerName.ptr) == 0) {
      layerFound = true;
      break;
    }
  }
  SDL_Log("Layer: %s was %sfound", layerName, toStringz((layerFound? "": "not")));
  return(layerFound);
}

void createDebugCallback(ref App app){
  // Hook instance function
  vkDebugCallback = cast(PFN_vkCreateDebugReportCallbackEXT) vkGetInstanceProcAddr(app.instance, "vkCreateDebugReportCallbackEXT");
  vkDestroyDebugCallback = cast(PFN_vkDestroyDebugReportCallbackEXT) vkGetInstanceProcAddr(app.instance, "vkDestroyDebugReportCallbackEXT");

  // Create Debug callback
  VkDebugReportCallbackCreateInfoEXT createDebug = {
    sType : VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
    flags : VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT | VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT,
    pfnCallback : &debugCallback,
    pUserData : null
  };
  vkDebugCallback(app.instance, &createDebug, app.allocator, &app.debugReport);
}


