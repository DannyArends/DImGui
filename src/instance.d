import engine;
import extensions;

void createInstance(ref App app){
  auto layers = app.queryInstanceLayerProperties();
  auto extensions = app.queryInstanceExtensionProperties();

  if(layers.has("VK_LAYER_KHRONOS_validation")){ app.layers ~= "VK_LAYER_KHRONOS_validation"; }
  if(extensions.has("VK_EXT_debug_report")){ app.instanceExtensions ~= "VK_EXT_debug_report"; }

  VkInstanceCreateInfo createInstance = { 
    sType : VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    enabledLayerCount : cast(uint)app.layers.length,
    ppEnabledLayerNames : &app.layers[0],
    enabledExtensionCount : cast(uint)app.instanceExtensions.length,
    ppEnabledExtensionNames : &app.instanceExtensions[0],
    pApplicationInfo: &app.applicationInfo
  };

  enforceVK(vkCreateInstance(&createInstance, app.allocator, &app.instance));
  SDL_Log("vkCreateInstance[layers:%d, extensions:%d]: %p", app.layers.length, app.instanceExtensions.length, app.instance );
}
