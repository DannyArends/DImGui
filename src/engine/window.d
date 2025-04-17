import engine;

import std.algorithm : sort;
import std.traits : EnumMembers;

import depthbuffer : createDepthResources, destroyDepthBuffer;
import descriptor : createDescriptorPool, createDescriptorSetLayout, createDescriptorSet;
import commands : createImGuiCommandBuffers, createRenderCommandBuffers, recordRenderCommandBuffer;
import framebuffer : createFramebuffers;
import pipeline : createGraphicsPipeline, deAllocate;
import renderpass : createRenderPass;
import surface : querySurfaceCapabilities;
import swapchain : createSwapChain, aquireSwapChainImages;
import sync : createSyncObjects;
import geometry : distance;
import uniforms : createUniforms, destroyUniforms;

VkPrimitiveTopology[] supportedTopologies = 
[
  VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
  VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
  VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN
];

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
  app.createDepthResources();
  app.createUniforms();
  app.createDescriptorPool();
  app.createDescriptorSetLayout();
  app.createDescriptorSet();
  app.renderpass = app.createRenderPass();
  app.imguiPass = app.createRenderPass(VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_ATTACHMENT_LOAD_OP_LOAD);
  app.createFramebuffers();
  app.createImGuiCommandBuffers();

  foreach(member; supportedTopologies){
    app.pipelines[member] = app.createGraphicsPipeline(member);
  }
  app.createRenderCommandBuffers();
  app.recordRenderCommandBuffer();
  app.createSyncObjects();
  //app.objects.sort!("a.distance > b.distance")(app.camera);  // Sort the 3D objects by distance
}

void destroyFrameData(ref App app) {
  for (uint i = 0; i < app.sync.length; i++) {
    vkDestroySemaphore(app.device, app.sync[i].imageAcquired, app.allocator);
    vkDestroySemaphore(app.device, app.sync[i].renderComplete, app.allocator);
  }
  for (uint i = 0; i < app.imageCount; i++) {
    vkDestroyFence(app.device, app.fences[i], app.allocator);
    vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.imguiBuffers[i]);
    vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.renderBuffers[i]);
    vkDestroyImageView(app.device, app.swapChainImageViews[i], app.allocator);
    vkDestroyFramebuffer(app.device, app.swapChainFramebuffers[i], app.allocator);
  }
  if(app.descriptorSetLayout) vkDestroyDescriptorSetLayout(app.device, app.descriptorSetLayout, app.allocator);
  if(app.uniform.uniformBuffers) app.destroyUniforms();
  if(app.descriptorPool) vkDestroyDescriptorPool(app.device, app.descriptorPool, app.allocator);
  if(app.depthBuffer.depthImage) app.destroyDepthBuffer();
  if(app.pipelines) app.deAllocate(app.pipelines);
  if(app.imguiPass) vkDestroyRenderPass(app.device, app.imguiPass, app.allocator);
  if(app.renderpass) vkDestroyRenderPass(app.device, app.renderpass, app.allocator);
}

void checkForResize(ref App app){
  int width, height;
  SDL_GetWindowSize(app.window, &width, &height);
  if(width > 0 && height > 0 && (app.rebuild || app.camera.width != width || app.camera.height != height)) {
    ImGui_ImplVulkan_SetMinImageCount(app.camera.minImageCount);
    app.createOrResizeWindow();
    app.frameIndex = 0;
    app.rebuild = false;
  }
}

