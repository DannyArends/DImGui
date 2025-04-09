import engine;
import validation;

import commands : createCommandPool;
import descriptor : createImGuiDescriptorPool;
import devices : pickPhysicalDevice, createLogicalDevice;
import events : handleEvents;
import frame : presentFrame, renderFrame;
import imgui : initializeImGui;
import instance : createInstance;
import pipeline : destroyPipeline;
import sdl : initializeSDL;
import surface : createSurface, querySurfaceCapabilities;
import textures : loadTexture, destroyTexture;
import window: createOrResizeWindow, checkForResize, renderGUI, destroyFrameData;

import matrix : mat4, scale, translate;

void main(string[] args) {
  App app = initializeSDL();
  app.createInstance();
  app.createDebugCallback();
  app.createLogicalDevice();
  app.createCommandPool();
  auto texture = app.loadTexture("./assets/textures/viking_room.png");
  app.createImGuiDescriptorPool();
  for(int x = -2; x < 0; x++){
    for(int y = 0; y < 2; y++){
      mat4 instance;
      auto scalefactor = 0.2f;
      instance = scale(instance, [scalefactor, scalefactor, scalefactor]);
      instance = translate(instance, [cast(float) x /4.0f, cast(float)y /4.0f, 0.5f]);
      app.objects[0].instances ~= instance;
    }
  }
  app.objects[0].buffer(app);
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
  app.objects[0].destroy(app);
  app.destroyTexture(texture);
  vkDestroyCommandPool(app.device, app.commandPool, app.allocator);
  vkDestroyDebugCallback(app.instance, app.debugCallback, app.allocator);
  vkDestroyDevice(app.device, app.allocator);

  vkDestroySurfaceKHR(app.instance, app.surface, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);

  SDL_DestroyWindow(app);
  SDL_Quit();
}

