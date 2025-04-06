import engine;
import extensions;
import descriptor;
import devices;
import commands;
import frame;
import framebuffer;
import imgui;
import instance;
import sdl;
import surface;
import swapchain;
import sync;
import renderpass;
import validation;

void createOrResizeWindow(ref App app, uint queueFamily) {
  enforceVK(vkDeviceWaitIdle(app.device));
  app.cleanFrameData();

  app.loadSurfaceCapabilities();
  app.createSwapChain(app.swapChain);
  app.aquireSwapChainImages();
  app.createRenderPass();
  app.createFramebuffers();
  app.createCommandBuffers(queueFamily);
  app.createSyncObjects();
}

void main(string[] args) {
  App app = loadSDL();
  app.loadInstanceExtensions();
  app.createInstance();
  app.createDebugCallback();
  uint queueFamily = app.createPhysicalDevice(1);

  // Get the Queue from the queueFamily
  vkGetDeviceQueue(app.device, queueFamily, 0, &app.queue);
  SDL_Log("vkGetDeviceQueue[family:%d]: %p", queueFamily, app.queue);

  app.createDescriptorPool(); // Create Descriptor Pool

  // Get a SDL_Vulkan surface
  SDL_Vulkan_CreateSurface(app, app.instance, &app.surface);
  SDL_Log("SDL_Vulkan_CreateSurface: %p", app.surface);

  app.createOrResizeWindow(queueFamily); // Create swapchain, renderpass, framebuffers, etc
  app.initImGui(queueFamily); // initialize ImGui (IO, Style)

  // Main loop
  bool done = false;
  bool demo = true;
  while (!done) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      ImGui_ImplSDL2_ProcessEvent(&event);
      if(event.type == SDL_QUIT) done = true;
      if(event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_CLOSE && event.window.windowID == SDL_GetWindowID(app)) done = true;
    }
    if(SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) { SDL_Delay(10); continue; }

    int width, height;
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
    if(demo) igShowDemoWindow(&demo);
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
  app.cleanFrameData();

  vkDestroyDescriptorPool(app.device, app.descriptorPool, app.allocator);
  vkDestroyDebugCallback(app.instance, app.debugCallback, app.allocator);
  vkDestroyDevice(app.device, app.allocator);

  vkDestroySurfaceKHR(app.instance, app.surface, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);

  SDL_DestroyWindow(app);
  SDL_Quit();
  return;
}
