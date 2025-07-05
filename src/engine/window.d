/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import compute: createComputeCommandBuffers, createComputePipeline;
import depthbuffer : createDepthResources;
import descriptor : createDescriptors, updateDescriptorSet;
import commands : createImGuiCommandBuffers, createRenderCommandBuffers;
import framebuffer : createFramebuffers;
import images : createColorResources;
import pipeline : createGraphicsPipeline;
import renderpass : createRenderPass;
import surface : querySurfaceCapabilities;
import shadowmap : createShadowMapGraphicsPipeline,   createShadowMapCommandBuffers;
import reflection : reflectShaders, createResources;
import swapchain : createSwapChain, aquireSwapChainImages;
import sync : createSyncObjects;

VkPrimitiveTopology[] supportedTopologies = 
[
  VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
  VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
  VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN
];

/** 
 * Called on Window creation and Resize, should rebuild all perFrame objects
 */
void createOrResizeWindow(ref App app) {
  if(app.verbose) SDL_Log("Window Created or ReSized, recreate SwapChain");
  enforceVK(vkDeviceWaitIdle(app.device));
  app.frameDeletionQueue.flush();

  // Query window settings then create a SwapChain, DepthBuffer, ColorBuffer, and Synchronization
  app.querySurfaceCapabilities();
  app.createSwapChain(app.swapChain);
  app.aquireSwapChainImages();
  app.createColorResources();
  app.createDepthResources();
  app.createSyncObjects();

  // Do reflection on the compute shaders, and create the compute command buffers and pipelines
  if (app.compute.enabled) {
    app.reflectShaders(app.compute.shaders);
    app.createResources(app.compute.shaders, COMPUTE);
    foreach(ref shader; app.compute.shaders) {
      app.createComputeCommandBuffers(shader);
      app.createComputePipeline(shader);
      for (uint i = 0; i < app.framesInFlight; i++) { app.updateDescriptorSet([shader], app.sets[shader.path], i); }
    }
  }

  // Do reflection on the shadow shaders 
  // TODO: Could be done once inside the main deletion queue, but then UBO reflection needs to allow a custome deletion queue
  app.reflectShaders(app.shadows.shaders);
  app.createResources(app.shadows.shaders, SHADOWS);
  app.createShadowMapCommandBuffers();
  app.createShadowMapGraphicsPipeline();
  for (uint i = 0; i < app.framesInFlight; i++) {
    app.updateDescriptorSet(app.shadows.shaders, app.sets[SHADOWS], i);
  }

  // Do reflection on the render shaders
  app.reflectShaders(app.shaders);
  app.createResources(app.shaders, RENDER);
  app.createDescriptors();

  // ImGui resources
  app.createImGuiCommandBuffers();

  // Create RenderPass, FrameBuffers, render command buffers and the render pipelines
  app.renderpass = app.createRenderPass();
  app.createFramebuffers();
  app.imguipass = app.createRenderPass(VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_ATTACHMENT_LOAD_OP_LOAD);

  app.createRenderCommandBuffers();
  foreach(member; supportedTopologies) { app.createGraphicsPipeline(member); }
  if(app.verbose) SDL_Log("Window Done");
}

/** 
 * Check if the window was resized, and if so recreate the window resources
 */
void checkForResize(ref App app){
  int width, height;
  SDL_GetWindowSize(app.window, &width, &height);
  if(width > 0 && height > 0 && (app.rebuild || app.camera.width != width || app.camera.height != height)) {
    ImGui_ImplVulkan_SetMinImageCount(app.camera.minImageCount);
    app.gui.io.DisplaySize = ImVec2(cast(float)width, cast(float)height);
    app.createOrResizeWindow();
    app.syncIndex = app.frameIndex = 0;
    app.rebuild = false;
  }
}
