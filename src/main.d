import engine;
import validation;

import commands : createCommandPool;
import descriptor : createImGuiDescriptorPool;
import devices : pickPhysicalDevice, createLogicalDevice;
import events : handleEvents;
import frame : presentFrame, renderFrame;
import glyphatlas : loadGlyphAtlas, createTextureImage;
import imgui : initializeImGui;
import instance : createInstance;
import pipeline : destroyPipeline;
import sdl : initializeSDL;
import surface : createSurface, querySurfaceCapabilities;
import textures : loadTexture, createSampler, destroyTexture;
import window: createOrResizeWindow, checkForResize, renderGUI, destroyFrameData;
import geometry : Instance;
import matrix : mat4, scale, translate, rotate;

void main(string[] args) {
  App app = initializeSDL();
  
  auto g = loadGlyphAtlas("./assets/fonts/FreeMono.ttf");
  
  app.createInstance();
  app.createDebugCallback();
  app.createLogicalDevice();
  app.createCommandPool();
  app.createSampler();
  app.textures ~= app.createTextureImage(g.surface);
  app.textures ~= app.loadTexture("./assets/textures/grunge.png");
  app.textures ~= app.loadTexture("./assets/textures/viking_room.png");

  app.createImGuiDescriptorPool();

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
  //Buffer the Cube
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
  for (uint i = 0; i < app.objects.length; i++) {
    app.objects[i].destroy(app);
  }
  foreach(texture; app.textures){
    app.destroyTexture(texture);
  }
  vkDestroySampler(app.device, app.sampler, null);
  vkDestroyCommandPool(app.device, app.commandPool, app.allocator);
  vkDestroyDebugCallback(app.instance, app.debugCallback, app.allocator);
  vkDestroyDevice(app.device, app.allocator);

  vkDestroySurfaceKHR(app.instance, app.surface, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);

  SDL_DestroyWindow(app);
  SDL_Quit();
}

