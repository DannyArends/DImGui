/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import compute: createComputeCommandBuffers, createComputePipeline;
import depthbuffer : createDepthResources;
import descriptor : createDescriptors, updateDescriptorSet;
import commands : createCommandBuffer;
import framebuffer : createFramebuffers;
import images : createColorResources;
import pipeline : createGraphicsPipeline, createPostProcessGraphicsPipeline;
import renderpass : createSceneRenderPass, createPostProcessRenderPass, createImGuiRenderPass;
import shadow : createShadowMapGraphicsPipeline, recordShadowCommandBuffer;
import reflection : reflectShaders, createResources;
import surface : querySurfaceFormats;
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
  app.swapDeletionQueue.flush();

  SDL_Log("0: Query window settings then create a SwapChain, DepthBuffer, ColorBuffer, and Synchronization");
  app.querySurfaceFormats();
  app.createSwapChain(app.swapChain);
  app.aquireSwapChainImages();
  app.createColorResources();
  app.createDepthResources();
  app.createSyncObjects();

  if (app.compute.enabled) {
    SDL_Log("1: Compute shaders reflection");
    app.reflectShaders(app.compute.shaders);
    app.createResources(app.compute.shaders, COMPUTE);
    foreach(ref shader; app.compute.shaders) {
      app.createComputeCommandBuffers(shader);
      app.createComputePipeline(shader);
      for (uint i = 0; i < app.framesInFlight; i++) { 
        app.updateDescriptorSet([shader], app.sets[shader.path], i);
      }
    }
  }

  SDL_Log("2: Shadow shaders reflection");
  app.reflectShaders(app.shadows.shaders);
  app.createResources(app.shadows.shaders, SHADOWS);
  app.createDescriptors(app.shadows.shaders, SHADOWS);
  app.createCommandBuffer(app.shadowBuffers, app.commandPool, app.framesInFlight);
  app.createShadowMapGraphicsPipeline();

  SDL_Log("3: Render shaders reflection");
  app.reflectShaders(app.shaders);
  app.createResources(app.shaders, RENDER);
  app.createDescriptors(app.shaders, RENDER);
  app.createCommandBuffer(app.renderBuffers, app.commandPool, app.framesInFlight);

  SDL_Log("4: Post-processing shaders reflection");
  app.reflectShaders(app.postProcess);
  app.createResources(app.postProcess, POST);
  app.createDescriptors(app.postProcess, POST);
  for (uint i = 0; i < app.framesInFlight; i++) {
    app.updateDescriptorSet(app.postProcess, app.sets[POST], i);
  }

  SDL_Log("5: ImGui resources");
  app.createCommandBuffer(app.imguiBuffers, app.commandPool, app.framesInFlight);

  SDL_Log("6: Create RenderPasses [SCENE -> POST -> IMGUI]");
  app.scene = app.createSceneRenderPass();
  app.postprocess = app.createPostProcessRenderPass();
  app.imgui = app.createImGuiRenderPass();

  SDL_Log("7: Create Framebuffers");
  app.createFramebuffers();

  SDL_Log("8: Create the Pipelines (Post-processing and Rendering)");
  app.createPostProcessGraphicsPipeline();
  foreach(member; supportedTopologies) {
    app.createGraphicsPipeline(member);
  }
  if(app.verbose) SDL_Log(" ---- Window Done ----");
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
    app.createOrResizeWindow();                         // Resize the window
    app.rebuild = app.syncIndex = app.frameIndex = 0;   // SwapChain is new, so reset syncronization
    if(app.verbose) SDL_Log("Window: %d images of [%d == %d, %d == %d]", app.camera.minImageCount, app.camera.width, width, app.camera.height, height);
  }
}
