/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Load Instance Extensions */
void loadInstanceExtensions(ref App app) {
  if(app.verbose) SDL_Log("loadInstanceExtensions");
  uint nExtensions;
  auto exts = SDL_Vulkan_GetInstanceExtensions(&nExtensions);
  app.instanceExtensions = exts[0..nExtensions].dup;
  if(app.verbose) {
    SDL_Log("Found %d instance extensions", app.instanceExtensions.length);
    for(uint i = 0; i < app.instanceExtensions.length; i++){ SDL_Log("- %s", app.instanceExtensions[i]); }
  }
}

/** Vulkan enumerate-twice idiom: count, allocate, fill. fn performs the actual Vulkan call. */
T[] enumerate(T)(ref App app, string what, scope VkResult delegate(uint*, T*) fn) {
  if(app.verbose) SDL_Log("query %s", toStringz(what));
  uint n;
  T[] items;
  fn(&n, null);                    // count (result ignored, as before)
  if(n == 0) return items;
  items.length = n;
  enforceVK(fn(&n, &items[0]));     // fill
  if(app.verbose) SDL_Log("Found %d %s", items.length, toStringz(what));
  return items;
}

/** query Instance Extensions Properties */
VkExtensionProperties[] queryInstanceExtensionProperties(ref App app, const(char)* layer = null) {
  return app.enumerate!VkExtensionProperties("instance extensions",
    (uint* n, VkExtensionProperties* p) => vkEnumerateInstanceExtensionProperties(layer, n, p));
}

/** query Instance Layer Properties */
VkLayerProperties[] queryInstanceLayerProperties(ref App app) {
  return app.enumerate!VkLayerProperties("instance layers",
    (uint* n, VkLayerProperties* p) => vkEnumerateInstanceLayerProperties(n, p));
}

/** query Device Extensions Properties */
VkExtensionProperties[] queryDeviceExtensionProperties(ref App app) {
  return app.enumerate!VkExtensionProperties("device extensions",
    (uint* n, VkExtensionProperties* p) => vkEnumerateDeviceExtensionProperties(app.physicalDevice, null, n, p));
}

bool has(VkLayerProperties[] layers, const(char)* layerName) {
  for(uint i = 0 ; i < layers.length; i++) { if(strcmp(layers[i].layerName.ptr, layerName) == 0) return true; }
  return false;
}

bool has(VkExtensionProperties[] properties, const(char)* extensionName) {
  for(uint i = 0 ; i < properties.length; i++) { if(strcmp(properties[i].extensionName.ptr, extensionName) == 0) return true; }
  return false;
}

