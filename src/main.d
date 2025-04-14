import engine;
import validation;

import commands : createCommandPool;
import descriptor : createImGuiDescriptorPool;
import devices : pickPhysicalDevice, createLogicalDevice;
import events : handleEvents;
import frame : presentFrame, renderFrame;
import glyphatlas : loadGlyphAtlas, createTextureImage;
import icosahedron : refineIcosahedron;
import imgui : initializeImGui;
import instance : createInstance;
import pipeline : destroyPipeline;
import sdl : initializeSDL;
import text : Text;
import surface : createSurface, querySurfaceCapabilities;
import textures : loadTextures, createSampler, destroyTexture;
import window: createOrResizeWindow, checkForResize, renderGUI, destroyFrameData;
import geometry : Instance, computeNormals, destroyObject;
import matrix : mat4, scale, translate, rotate;

void main(string[] args) {
  App app = initializeSDL();
  
  auto g = loadGlyphAtlas("./assets/fonts/FreeMono.ttf", 80, '\U000000FF', 1024);
  
  app.createInstance();
  app.createDebugCallback();
  app.createLogicalDevice();
  app.createCommandPool();
  app.createSampler();
  app.textures ~= app.createTextureImage(g.surface);
  app.loadTextures("./assets/textures/");
  app.createImGuiDescriptorPool();

  app.objects ~= Text(g);
  app.objects[3].instances[0] = rotate(app.objects[3].instances[0], [0.0f, 90.0f, 0.0f]);

  // Add a couple of instances to the cube
  for(int x = -10; x < 10; x++) {
    for(int z = -10; z < 10; z++) {
      mat4 instance;
      auto scalefactor = 0.25f;
      instance = scale(instance, [scalefactor, scalefactor, scalefactor]);
      instance = translate(instance, [cast(float) x /4.0f, -1.0f, cast(float)z /4.0f]);
      if(x <= 0 && z <= 0) app.objects[0].instances ~= Instance(0, instance);
      if(x > 0 && z > 0) app.objects[0].instances ~= Instance(1, instance);
      if(x <= 0 && z > 0) app.objects[0].instances ~= Instance(2, instance);
    }
  }
  app.objects[2].refineIcosahedron(4);
  app.objects[2].computeNormals();
  app.objects[2].instances[0] = scale(app.objects[2].instances[0], [5.0f, 5.0f, 5.0f]);

  app.objects[2].instances[0].tid = 6;
  app.objects[2].instances[0] = translate(app.objects[2].instances[0], [10.0f, 6.0f, 2.0f]);

  //Buffer the objects
  for (uint i = 0; i < app.objects.length; i++) {
    app.objects[i].buffer(app);
  }

  app.createSurface();
  app.createOrResizeWindow(); // Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui(); // Initialize ImGui (IO, Style, etc)

  uint frames = 4000;
  while (!app.finished && app.totalFramesRendered < frames) { // Main loop
    app.handleEvents();
    if(SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) { SDL_Delay(10); continue; }

    app.checkForResize();
    ImDrawData* drawData = app.renderGUI();

    app.renderFrame(drawData);
    app.presentFrame();
    app.totalFramesRendered++;
  }
  enforceVK(vkDeviceWaitIdle(app.device));
  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);
  app.destroyFrameData();

  vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator);
  vkDestroyDescriptorPool(app.device, app.imguiPool, app.allocator);
  foreach(object; app.objects) { app.destroyObject(object); }
  foreach(texture; app.textures) { app.destroyTexture(texture); }
  vkDestroySampler(app.device, app.sampler, null);
  vkDestroyCommandPool(app.device, app.commandPool, app.allocator);
  vkDestroyDebugCallback(app.instance, app.debugCallback, app.allocator);
  vkDestroyDevice(app.device, app.allocator);

  vkDestroySurfaceKHR(app.instance, app.surface, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);

  SDL_DestroyWindow(app);
  SDL_Quit();
}

