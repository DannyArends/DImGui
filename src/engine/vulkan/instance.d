/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import extensions : loadInstanceExtensions, queryInstanceLayerProperties, queryInstanceExtensionProperties, has;
import validation : createDebugUtils;

/** Load instance extensions and create the Vulkan instance */
void createInstance(ref App app){
  app.loadInstanceExtensions();

  uint lVer = VK_MAKE_API_VERSION( 0, 1, 1, 0 );   // Accept 1.1
  vkEnumerateInstanceVersion(&lVer);               // Find loader Version
  if(lVer < app.applicationInfo.apiVersion){ app.applicationInfo.apiVersion = lVer; } // request 1.2 or lVer

  auto layers = app.queryInstanceLayerProperties();
  auto extensions = app.queryInstanceExtensionProperties();

  if(app.enableValidation) {
    if(layers.has("VK_LAYER_KHRONOS_validation")){ app.layers ~= "VK_LAYER_KHRONOS_validation"; }
    if(extensions.has("VK_EXT_debug_report")){ app.instanceExtensions ~= "VK_EXT_debug_report"; }
    if(extensions.has("VK_EXT_debug_utils")){ app.instanceExtensions ~= "VK_EXT_debug_utils"; }
    if(extensions.has("VK_KHR_get_physical_device_properties2")){ app.instanceExtensions ~= "VK_KHR_get_physical_device_properties2"; }
  }

  VkInstanceCreateInfo createInstance = { 
    sType : VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    enabledLayerCount : cast(uint)app.layers.length,
    ppEnabledLayerNames : (app.layers? &app.layers[0] : null),
    enabledExtensionCount : cast(uint)app.instanceExtensions.length,
    ppEnabledExtensionNames : (app.instanceExtensions? &app.instanceExtensions[0] : null),
    pApplicationInfo: &app.applicationInfo,
  };

  SDL_Log("vkCreateInstance[extensions:%d]", app.instanceExtensions.length);
  const(char)*[] filtered;
  foreach(e; app.instanceExtensions) { if(extensions.has(e)) { filtered ~= e; 
    } else { SDL_Log("Dropping unsupported instance extension: %s", e); }
  }
  app.instanceExtensions = filtered;
  SDL_Log("Filtered [extensions:%d]", app.instanceExtensions.length);
  enforceVK(vkCreateInstance(&createInstance, app.allocator, &app.instance));
  app.mainDeletionQueue.add((){
    if(app.instance != null) { if(app.verbose) SDL_Log("Destroy instance: %p", app.instance);
      vkDestroyInstance(app.instance, app.allocator);
    }
  });
  app.createDebugUtils();
  if(app.verbose) SDL_Log("vkCreateInstance[layers:%d, extensions:%d]: %p", app.layers.length, app.instanceExtensions.length, app.instance );
}
