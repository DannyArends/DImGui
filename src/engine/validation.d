/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : Colors;

PFN_vkCreateDebugReportCallbackEXT  vkDebugCallback;
PFN_vkDestroyDebugReportCallbackEXT vkDestroyDebugCallback;
PFN_vkSetDebugUtilsObjectNameEXT    vkSetDebugUtilsObjectName;
PFN_vkCmdBeginDebugUtilsLabelEXT    vkCmdBeginDebugUtilsLabel;
PFN_vkCmdEndDebugUtilsLabelEXT      vkCmdEndDebugUtilsLabel;

extern(C) uint debugCallback(VkDebugReportFlagsEXT flags, VkDebugReportObjectTypeEXT objectType, uint64_t object, 
                             size_t location, int32_t messageCode, const char* pLayerPrefix, const char* pMessage, void* pUserData) {
    SDL_Log("[debugCallback] Debug report from ObjectType: %d\nMessage %d: %s\n", objectType, messageCode, pMessage);
    return VK_FALSE;
}

void createDebugCallback(ref App app){
  // Hook instance function
  vkDebugCallback = cast(PFN_vkCreateDebugReportCallbackEXT) vkGetInstanceProcAddr(app.instance, "vkCreateDebugReportCallbackEXT");

  // Create Debug callback
  VkDebugReportCallbackCreateInfoEXT createDebug = {
    sType : VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
    flags : VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT | VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT,
    pfnCallback : &debugCallback,
    pUserData : null
  };
  vkDebugCallback(app.instance, &createDebug, app.allocator, &app.debugCallback);

  app.mainDeletionQueue.add((){
    vkDestroyDebugCallback = cast(PFN_vkDestroyDebugReportCallbackEXT) vkGetInstanceProcAddr(app.instance, "vkDestroyDebugReportCallbackEXT");
    vkDestroyDebugCallback(app.instance, app.debugCallback, app.allocator);
  });
}

void createDebugUtils(ref App app) {
  vkSetDebugUtilsObjectName = cast(PFN_vkSetDebugUtilsObjectNameEXT)vkGetInstanceProcAddr(app.instance, "vkSetDebugUtilsObjectNameEXT");
  vkCmdBeginDebugUtilsLabel = cast(PFN_vkCmdBeginDebugUtilsLabelEXT)vkGetInstanceProcAddr(app.instance, "vkCmdBeginDebugUtilsLabelEXT");
  vkCmdEndDebugUtilsLabel = cast(PFN_vkCmdEndDebugUtilsLabelEXT)vkGetInstanceProcAddr(app.instance, "vkCmdEndDebugUtilsLabelEXT");
}

void nameVulkanObject(T)(ref App app, T object, const(char)* name, VkObjectType objectType = VK_OBJECT_TYPE_RENDER_PASS){
  VkDebugUtilsObjectNameInfoEXT nameInfo = {
      sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
      pNext: null,
      objectType: objectType,
      objectHandle: cast(ulong)object,
      pObjectName: name
  };
  if (vkSetDebugUtilsObjectName !is null) { vkSetDebugUtilsObjectName(app.device, &nameInfo); }
}

void pushLabel(T)(T object, const(char)* name, Colors color = Colors.lightslategrey) {
  VkDebugUtilsLabelEXT labelInfo = {
    sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT,
    pLabelName: name, color: color
  };
  if(vkCmdBeginDebugUtilsLabel) vkCmdBeginDebugUtilsLabel(object, &labelInfo);
}

void popLabel(T)(T object) {
  if(vkCmdEndDebugUtilsLabel){ vkCmdEndDebugUtilsLabel(object); }
}

