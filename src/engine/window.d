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
  //if(app.showdemo) igShowDemoWindow(&app.showdemo);
  igSetNextWindowPos(ImVec2(0.0f, 0.0f), 0, ImVec2(0.0f, 0.0f));
  auto flags = ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;
  igBegin("FPS", null, flags);
    igText("%s", app.properties.deviceName.ptr);
    igText("Vulkan v%d.%d.%d", VK_API_VERSION_MAJOR(app.properties.apiVersion),
                       VK_API_VERSION_MINOR(app.properties.apiVersion),
                       VK_API_VERSION_PATCH(app.properties.apiVersion));
    igText("%.1f FPS, %.1f ms", app.io.Framerate, 1000.0f / app.io.Framerate);
    igText("C: [%.1f, %.1f, %.1f]", app.camera.position[0], app.camera.position[1], app.camera.position[2]);
    igText("F: [%.1f, %.1f, %.1f]", app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2]);
  igEnd();
  igSetNextWindowPos(ImVec2(0, app.io.DisplaySize.y - 40), ImGuiCond_Always, ImVec2(0.0f,0.0f));
  igBegin("Main Menu", null, ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_AlwaysAutoResize);
    if(igButton("BTN1", ImVec2(0.0f, 0.0f))){ SDL_Log("Pressed BTN1"); } igSameLine(0,5);
    if(igButton("BTN2", ImVec2(0.0f, 0.0f))){ SDL_Log("Pressed BTN2"); } igSameLine(0,5);
    if(igButton("BTN3", ImVec2(0.0f, 0.0f))){ SDL_Log("Pressed BTN3"); } igSameLine(0,5);
    if(igButton("BTN4", ImVec2(0.0f, 0.0f))){ SDL_Log("Pressed BTN4"); }
  igEnd();
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

