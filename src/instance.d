import includes;
import std.string : toStringz;
import application : App;
import vkdebug : enforceVK, checkValidationLayerSupport;

bool isExtensionAvailable(VkExtensionProperties[] properties, string extension) {
  for(uint32_t i = 0 ; i < properties.length; i++) {
    if (strcmp(toStringz(properties[i].extensionName), toStringz(extension)) == 0) return true;
  }
  return false;
}

void createInstance(ref App app) {
  // Create instance
  VkInstanceCreateInfo createInstance = { 
    sType : VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    enabledLayerCount : 1,
    ppEnabledLayerNames : &app.validationLayers[0],
    enabledExtensionCount : cast(uint)app.extensions.length,
    ppEnabledExtensionNames : &app.extensions[0],
    pApplicationInfo: &app.applicationInfo
  };

  vkCreateInstance(&createInstance, app.allocator, &app.instance);
  SDL_Log("vkCreateInstance: %p", app.instance);
}

void loadInstanceExtensions(ref App app) {
  uint32_t nExtensions;
  SDL_Vulkan_GetInstanceExtensions(app, &nExtensions, null);
  app.extensions.length = nExtensions;
  SDL_Vulkan_GetInstanceExtensions(app, &nExtensions, &app.extensions[0]);
  SDL_Log("Number of available instance extensions: %d", nExtensions);

  // Enable required extensions
  if (isExtensionAvailable(app.properties, "VK_KHR_get_physical_device_properties2")){
    app.addExtension("VK_KHR_get_physical_device_properties2");
  }

  if(app.checkValidationLayerSupport("VK_LAYER_KHRONOS_validation")) { // Add Debug extension
    app.validationLayers = ["VK_LAYER_KHRONOS_validation"];
    app.addExtension("VK_EXT_debug_report");
  }
}

void addExtension(ref App app, string extension) {
  app.extensions.length += 1;
  app.extensions[app.extensions.length-1] = toStringz(extension);
}

void loadExtensionProperties(ref App app) {
  uint32_t nProperties;
  vkEnumerateInstanceExtensionProperties(null, &nProperties, null);
  app.properties.length = nProperties;
  enforceVK(vkEnumerateInstanceExtensionProperties(null, &nProperties, &app.properties[0]));

  SDL_Log("Number of available instance extensions properties: %d", nProperties);
  foreach(i, property; app.properties) { 
    if(app.verbose) SDL_Log("- %s", toStringz(property.extensionName));
  }
}

