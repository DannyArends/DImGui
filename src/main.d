import includes;

import std.string : toStringz;
import core.stdc.string : strcmp;
import application : App;
import sdl : printSoundDecoders, initSDL, quitSDL;
import vkdebug : enforceVK, vkDestroyDebugCallback;
import vulkan : setupVulkan;

static void SetupVulkanWindow(ref App app, ImGui_ImplVulkanH_Window* wd, VkSurfaceKHR surface, int width, int height) {
  SDL_Log("SetupVulkanWindow");
  wd.Surface = surface;

  // Check for WSI support
  VkBool32 isSupported;
  vkGetPhysicalDeviceSurfaceSupportKHR(app.physicalDevice, app.queueFamily, wd.Surface, &isSupported);
  if (!isSupported) {
    SDL_Log("[vulkan] Error no WSI support on physical device 0");
    abort();
  }

  // Select Image & ColorSpace Format
  VkFormat[] rImageFormat = [ VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8_UNORM, VK_FORMAT_R8G8B8_UNORM ];
  VkColorSpaceKHR rColorSpace = VK_COLORSPACE_SRGB_NONLINEAR_KHR;
  wd.SurfaceFormat = ImGui_ImplVulkanH_SelectSurfaceFormat(app.physicalDevice, wd.Surface, &rImageFormat[0], cast(int)rImageFormat.length, rColorSpace);

  // Select presentMode
  VkPresentModeKHR[] presentModes = [ VK_PRESENT_MODE_FIFO_KHR ];
  //VkPresentModeKHR[] presentModes = [ VK_PRESENT_MODE_MAILBOX_KHR, VK_PRESENT_MODE_IMMEDIATE_KHR, VK_PRESENT_MODE_FIFO_KHR ];
  wd.PresentMode = ImGui_ImplVulkanH_SelectPresentMode(app.physicalDevice, wd.Surface, &presentModes[0], cast(int)presentModes.length);

  // Create ImGUI window
  ImGui_ImplVulkanH_CreateOrResizeWindow(app.instance, app.physicalDevice, app.dev, wd, app.queueFamily, app.allocator, width, height, app.minImageCnt);
  SDL_Log("Done with SetupVulkanWindow");
}

static void FrameRender(App app, ImDrawData* drawData) {
  VkSemaphore image_acquired_semaphore  = app.wd.FrameSemaphores.Data[app.wd.SemaphoreIndex].ImageAcquiredSemaphore;
  VkSemaphore render_complete_semaphore = app.wd.FrameSemaphores.Data[app.wd.SemaphoreIndex].RenderCompleteSemaphore;
  VkResult err = vkAcquireNextImageKHR(app.dev, app.wd.Swapchain, uint64_t.max, image_acquired_semaphore, cast(VkFence_T*)VK_NULL_HANDLE, &app.wd.FrameIndex);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuildSwapChain = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);

  ImGui_ImplVulkanH_Frame* fd = &app.wd.Frames.Data[app.wd.FrameIndex];

  {  // Wait for Fence
    enforceVK(vkWaitForFences(app.dev, 1, &fd.Fence, VK_TRUE, uint64_t.max));
    enforceVK(vkResetFences(app.dev, 1, &fd.Fence));
  }

  {  // Record command buffer
    enforceVK(vkResetCommandPool(app.dev, fd.CommandPool, 0));
    VkCommandBufferBeginInfo info = {
      sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
    };
    enforceVK(vkBeginCommandBuffer(fd.CommandBuffer, &info));
  }

  {  // RenderPass
    VkRect2D renderArea = { extent: { width: app.wd.Width, height: app.wd.Height } };

    VkRenderPassBeginInfo info = {
      sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      renderPass : app.wd.RenderPass,
      framebuffer : fd.Framebuffer,
      renderArea : renderArea,
      clearValueCount : 1,
      pClearValues : &app.wd.ClearValue
    };
    vkCmdBeginRenderPass(fd.CommandBuffer, &info, VK_SUBPASS_CONTENTS_INLINE);
  }

  ImGui_ImplVulkan_RenderDrawData(drawData, fd.CommandBuffer, cast(VkPipeline_T*)VK_NULL_HANDLE);

  // Submit command buffer
  vkCmdEndRenderPass(fd.CommandBuffer);
  {
    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo info = {
      sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
      waitSemaphoreCount : 1,
      pWaitSemaphores : &image_acquired_semaphore,
      pWaitDstStageMask : &wait_stage,
      commandBufferCount : 1,
      pCommandBuffers : &fd.CommandBuffer,
      signalSemaphoreCount : 1,
      pSignalSemaphores : &render_complete_semaphore,
    };
    enforceVK(vkEndCommandBuffer(fd.CommandBuffer));
    enforceVK(vkQueueSubmit(app.gfxQueue, 1, &info, fd.Fence));
  }
}

void FramePresent(ref App app) {
  if (app.rebuildSwapChain) return;
  VkSemaphore render_complete_semaphore = app.wd.FrameSemaphores.Data[app.wd.SemaphoreIndex].RenderCompleteSemaphore;
  VkPresentInfoKHR info = {
    sType : VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    waitSemaphoreCount : 1,
    pWaitSemaphores : &render_complete_semaphore,
    swapchainCount : 1,
    pSwapchains : &app.wd.Swapchain,
    pImageIndices : &app.wd.FrameIndex,
  };
  VkResult err = vkQueuePresentKHR(app.gfxQueue, &info);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuildSwapChain = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  app.wd.SemaphoreIndex = (app.wd.SemaphoreIndex + 1) % app.wd.SemaphoreCount; // Now we can use the next set of semaphores
}

void main(string[] args){
  App app;
  app.initSDL();            // initialize SDL
  app.setupVulkan();        // Setup Vulkan

  int w, h;
  SDL_GetWindowSize(app, &w, &h);
  app.SetupVulkanWindow(app.wd, app.surface, w, h);

  igCreateContext(null);
  SDL_Log("Done with igCreateContext");
  ImGuiIO* io = igGetIO_Nil(); cast(void)io;
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  //io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
  io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;         // Enable Docking
  //io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;     // Enable Multi-Viewport / Platform Windows

  // Setup Dear ImGui style
  igStyleColorsDark(null);

  // When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
  ImGuiStyle* style = igGetStyle();
  if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable){
    style.WindowRounding = 1.0f;
    style.Colors[ImGuiCol_WindowBg].w = 1.0f;
  }

  // Setup Platform/Renderer backends
  SDL_Log("ImGui_ImplSDL2_InitForVulkan");
  ImGui_ImplSDL2_InitForVulkan(app);
  SDL_Log("Done with ImGui_ImplSDL2_InitForVulkan");
  ImGui_ImplVulkan_InitInfo init_info = {
    Instance : app.instance,
    PhysicalDevice : app.physicalDevice,
    Device : app.dev,
    QueueFamily : app.queueFamily,
    Queue : app.gfxQueue,
    PipelineCache : app.pipelineCache,
    DescriptorPool : app.descriptorPool,
    RenderPass : app.wd.RenderPass,
    Subpass : 0,
    MinImageCount : app.minImageCnt,
    ImageCount : app.wd.ImageCount,
    MSAASamples : VK_SAMPLE_COUNT_1_BIT,
    Allocator : app.allocator,
    CheckVkResultFn : &enforceVK
  };
  SDL_Log("ImGui_ImplVulkan_Init");
  ImGui_ImplVulkan_Init(&init_info);

  bool show_demo_window = true;
  bool show_another_window = false;
  ImVec4 clear_color = { x : 0.45f, y : 0.55f, z : 0.60f, w : 1.00f };

    // Main loop
  bool done = false;
  while (!done){
    SDL_Event event;
    while (SDL_PollEvent(&event)){
      ImGui_ImplSDL2_ProcessEvent(&event);
      if (event.type == SDL_QUIT) done = true;
      if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_CLOSE && event.window.windowID == SDL_GetWindowID(app)) done = true;
    }
    if (SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) {
      SDL_Delay(10);
      continue;
    }
    SDL_GetWindowSize(app, &w, &h);
    if (w > 0 && h > 0 && (app.rebuildSwapChain || app.wd.Width != w || app.wd.Height != h)) {
      ImGui_ImplVulkan_SetMinImageCount(app.minImageCnt);
      ImGui_ImplVulkanH_CreateOrResizeWindow(app.instance, app.physicalDevice, app.dev, app.wd, app.queueFamily, app.allocator, w, h, app.minImageCnt);
      app.wd.FrameIndex = 0;
      app.rebuildSwapChain = false;
    }
    // Start ImGui frame
    ImGui_ImplVulkan_NewFrame();
    ImGui_ImplSDL2_NewFrame();
    igNewFrame();
    if (show_demo_window) igShowDemoWindow(&show_demo_window);

    // render the ImGUI data
    igRender();
    ImDrawData* drawData = igGetDrawData();
    const bool main_is_minimized = (drawData.DisplaySize.x <= 0.0f || drawData.DisplaySize.y <= 0.0f);
    app.wd.ClearValue.color.float32 = [clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w];

    // Render a frame
    if (!main_is_minimized) app.FrameRender(drawData);

    // Update and render additional Platform windows
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
      igUpdatePlatformWindows();
      igRenderPlatformWindowsDefault(null, null);
    }

    // Present frame
    if (!main_is_minimized) app.FramePresent();
  }

  // Cleanup
  enforceVK(vkDeviceWaitIdle(app.dev));
  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);
  ImGui_ImplVulkanH_DestroyWindow(app.instance, app.dev, app.wd, app.allocator);

  vkDestroyDescriptorPool(app.dev, app.descriptorPool, app.allocator);
  vkDestroyDebugCallback(app.instance, app.debugReport, app.allocator);
  vkDestroyDevice(app.dev, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);

  app.quitSDL();
  return;
}

