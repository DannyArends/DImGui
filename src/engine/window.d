/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.algorithm : sort;
import std.traits : EnumMembers;

import compute: createComputeBufferAndImage, createComputeDescriptorPool, createComputeDescriptorSet, createComputeDescriptorSetLayout, createComputePipeline;
import depthbuffer : createDepthResources;
import descriptor : createDescriptorPool, createDescriptorSetLayout, createRenderDescriptor, createTextureDescriptors;
import commands : createImGuiCommandBuffers, createRenderCommandBuffers;
import framebuffer : createFramebuffers;
import images : createColorResources;
import pipeline : createGraphicsPipeline;
import renderpass : createRenderPass;
import surface : querySurfaceCapabilities;
import swapchain : createSwapChain, aquireSwapChainImages;
import sync : createSyncObjects;
import uniforms : createRenderUBO;

VkPrimitiveTopology[] supportedTopologies = 
[
  VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
  VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
  VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN
];

void createOrResizeWindow(ref App app) {
  if(app.verbose) SDL_Log("Window created or resized, recreate SwapChain");
  enforceVK(vkDeviceWaitIdle(app.device));
  app.frameDeletionQueue.flush();

  // Query window settings then create a SwapChain, DepthBuffer, and ColorBuffer
  app.querySurfaceCapabilities();
  app.createSwapChain(app.swapChain);
  app.aquireSwapChainImages();
  app.createColorResources();
  app.createDepthResources();

  // Compute resources
  app.createComputeBufferAndImage();
  app.createComputeDescriptorPool();
  app.createComputeDescriptorSetLayout();
  app.createComputeDescriptorSet();

  // Render resources
  app.createRenderUBO();
  app.createDescriptorPool();
  app.createDescriptorSetLayout();
  app.createRenderDescriptor();
  app.createTextureDescriptors();

  // ImGui resources
  app.createImGuiCommandBuffers();

  // RenderPass, FrameBuffers, Render Pipelines, and Synchronization
  app.renderpass = app.createRenderPass();
  app.imguiPass = app.createRenderPass(VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_ATTACHMENT_LOAD_OP_LOAD);
  app.createFramebuffers();

  app.createComputePipeline();
  foreach(member; supportedTopologies) { 
    app.createGraphicsPipeline(member);
  }
  app.createRenderCommandBuffers();
  app.createSyncObjects();
}

void checkForResize(ref App app){
  int width, height;
  SDL_GetWindowSize(app.window, &width, &height);
  if(width > 0 && height > 0 && (app.rebuild || app.camera.width != width || app.camera.height != height)) {
    ImGui_ImplVulkan_SetMinImageCount(app.camera.minImageCount);
    app.createOrResizeWindow();
    app.syncIndex = app.frameIndex = 0;
    app.rebuild = false;
  }
}
