import engine;
import validation;

import commands : createCommandBuffers;
import descriptor : createDescriptorPool;
import devices : pickPhysicalDevice, createLogicalDevice;
import events : handleEvents;
import frame : destroyFrameData, presentFrame, renderFrame;
import framebuffer : createFramebuffers;
import imgui : initializeImGui;
import instance : createInstance;
import sdl : initializeSDL;
import surface : createSurface, querySurfaceCapabilities;
import swapchain : createSwapChain, aquireSwapChainImages;
import sync : createSyncObjects;
import renderpass : createRenderPass;

void createOrResizeWindow(ref App app, uint queueFamily) {
  enforceVK(vkDeviceWaitIdle(app.device));

  app.destroyFrameData();

  app.querySurfaceCapabilities();
  app.createSwapChain(app.swapChain);
  app.aquireSwapChainImages();
  app.createRenderPass();
  app.createFramebuffers();
  app.createCommandBuffers(queueFamily);
  app.createSyncObjects();
}

void main(string[] args) {
  App app = initializeSDL();
  app.createInstance();
  app.createDebugCallback();
  uint queueFamily = app.pickPhysicalDevice(1);
  app.createLogicalDevice(queueFamily);
  app.createDescriptorPool();
  app.createSurface();
  app.createOrResizeWindow(queueFamily); // Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui(queueFamily); // Initialize ImGui (IO, Style, etc)

  int width, height;
  while (!app.finished) { // Main loop
    app.handleEvents();
    if(SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) { SDL_Delay(10); continue; }

    SDL_GetWindowSize(app.window, &width, &height);
    if(width > 0 && height > 0 && (app.rebuild || app.width != width || app.height != height)) {
      ImGui_ImplVulkan_SetMinImageCount(app.capabilities.minImageCount);
      app.createOrResizeWindow(queueFamily);
      app.frameIndex = 0;
      app.rebuild = false;
    }

    // Start ImGui frame
    ImGui_ImplVulkan_NewFrame();
    ImGui_ImplSDL2_NewFrame();
    igNewFrame();
    if(app.showdemo) igShowDemoWindow(&app.showdemo);

    igRender();
    ImDrawData* drawData = igGetDrawData();

    app.renderFrame(drawData);
    app.presentFrame();
    app.totalFramesRendered++;
  }
  enforceVK(vkDeviceWaitIdle(app.device));
  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);
  app.destroyFrameData();

  vkDestroyDescriptorPool(app.device, app.descriptorPool, app.allocator);
  vkDestroyDebugCallback(app.instance, app.debugCallback, app.allocator);
  vkDestroyDevice(app.device, app.allocator);

  vkDestroySurfaceKHR(app.instance, app.surface, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);

  SDL_DestroyWindow(app);
  SDL_Quit();
}
