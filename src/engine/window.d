import engine;

import commands : createCommandBuffers;
import frame : destroyFrameData;
import framebuffer : createFramebuffers;
import renderpass : createRenderPass;
import surface : querySurfaceCapabilities;
import swapchain : createSwapChain, aquireSwapChainImages;
import sync : createSyncObjects;

ImDrawData* renderGUI(ref App app){
  // Start ImGui frame
  ImGui_ImplVulkan_NewFrame();
  ImGui_ImplSDL2_NewFrame();
  igNewFrame();
  if(app.showdemo) igShowDemoWindow(&app.showdemo);

  igRender();
  return(igGetDrawData());
}

void createOrResizeWindow(ref App app) {
  if(app.verbose) SDL_Log("Window ReSize, recreate SwapChain");
  enforceVK(vkDeviceWaitIdle(app.device));

  app.destroyFrameData();

  app.querySurfaceCapabilities();
  app.createSwapChain(app.swapChain);
  app.aquireSwapChainImages();
  app.createRenderPass();
  app.createFramebuffers();
  app.createCommandBuffers();
  app.createSyncObjects();
}

void checkForResize(ref App app){
  int width, height;
  SDL_GetWindowSize(app.window, &width, &height);
  if(width > 0 && height > 0 && (app.rebuild || app.width != width || app.height != height)) {
    ImGui_ImplVulkan_SetMinImageCount(app.capabilities.minImageCount);
    app.createOrResizeWindow();
    app.frameIndex = 0;
    app.rebuild = false;
  }
}
