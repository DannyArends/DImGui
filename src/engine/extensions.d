// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

import engine;

// Load Instance Extensions
void loadInstanceExtensions(ref App app) {
  if(app.verbose) SDL_Log("loadInstanceExtensions");
  uint nExtensions;
  SDL_Vulkan_GetInstanceExtensions(app.window, &nExtensions, null);
  app.instanceExtensions.length = nExtensions;
  SDL_Vulkan_GetInstanceExtensions(app.window, &nExtensions, &app.instanceExtensions[0]);
  if(app.verbose) SDL_Log("Found %d instance extensions", app.instanceExtensions.length);
  //if(app.verbose) for(uint i = 0; i < app.instanceExtensions.length; i++){ SDL_Log("- %s", app.instanceExtensions[i]); }
}

// query Instance Extensions Properties
VkExtensionProperties[] queryInstanceExtensionProperties(ref App app, const(char)* layer = null) {
  if(app.verbose) SDL_Log("queryInstanceExtensionProperties");
  uint nProperties;
  VkExtensionProperties[] properties;

  vkEnumerateInstanceExtensionProperties(layer, &nProperties, null);
  if(nProperties == 0) return properties;
  properties.length = nProperties;
  enforceVK(vkEnumerateInstanceExtensionProperties(layer, &nProperties, &properties[0]));
  if(app.verbose) SDL_Log("Found %d instance extensions", properties.length);
  //if(app.verbose) foreach(i, property; properties) { SDL_Log("-Extension[%d] %s", i, property.extensionName.ptr); }
  return(properties);
}

// query Instance Layer Properties
VkLayerProperties[] queryInstanceLayerProperties(ref App app) {
  if(app.verbose) SDL_Log("queryInstanceLayerProperties");
  uint nLayers;
  VkLayerProperties[] layers;

  vkEnumerateInstanceLayerProperties(&nLayers, null);
  layers.length = nLayers;
  enforceVK(vkEnumerateInstanceLayerProperties(&nLayers, &layers[0]));
  if(app.verbose) SDL_Log("Found %d layers", layers.length);
  //if(app.verbose) foreach(i, layer; layers) { SDL_Log("-Layer[%d] %s", i, layer.layerName.ptr); }
  return(layers);
}

// query Device Extensions Properties
VkExtensionProperties[] queryDeviceExtensionProperties(ref App app) {
  if(app.verbose) SDL_Log("queryDeviceExtensionProperties");
  uint nProperties;
  VkExtensionProperties[] properties;

  vkEnumerateDeviceExtensionProperties(app.physicalDevice, null, &nProperties, null);
  if(nProperties == 0) return properties;
  properties.length = nProperties;
  enforceVK(vkEnumerateDeviceExtensionProperties(app.physicalDevice, null, &nProperties, &properties[0]));
  if(app.verbose) SDL_Log("Found %d device extensions", properties.length);
  //if(app.verbose) foreach(i, property; properties) { SDL_Log("-Extension[%d] %s", i, property.extensionName.ptr); }
  return(properties);
}

bool has(VkLayerProperties[] layers, const(char)* layerName) {
  for(uint i = 0 ; i < layers.length; i++) { if(strcmp(layers[i].layerName.ptr, layerName) == 0) return true; }
  return false;
}

bool has(VkExtensionProperties[] properties, const(char)* extensionName) {
  for(uint i = 0 ; i < properties.length; i++) { if(strcmp(properties[i].extensionName.ptr, extensionName) == 0) return true; }
  return false;
}
