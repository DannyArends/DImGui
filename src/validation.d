import engine;

PFN_vkCreateDebugReportCallbackEXT  vkDebugCallback;
PFN_vkDestroyDebugReportCallbackEXT vkDestroyDebugCallback;

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
  vkDebugCallback(app.instance, &createDebug, app.allocator, &app.debugCallback);
}
