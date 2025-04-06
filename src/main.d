import engine;
import extensions;
import devices;
import commands;
import framebuffer;
import surface;
import swapchain;
import sync;
import renderpass;

App loadSDL() {
  App app;
  SDL_Init(SDL_INIT_VIDEO);
  SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
  app.window = SDL_CreateWindow("ImGUI", SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), 1280, 720, window_flags);
  SDL_Log("SDL_CreateWindow: %p", app.window);
  return(app);
}

void cleanFrameData(ref App app) {
  for (uint i = 0; i < app.sync.length; i++) {
    vkDestroySemaphore(app.device, app.sync[i].imageAcquired, app.allocator);
    vkDestroySemaphore(app.device, app.sync[i].renderComplete, app.allocator);
  }
  for (uint i = 0; i < app.imageCount; i++) {
    vkDestroyFence(app.device, app.fences[i], app.allocator);
    vkFreeCommandBuffers(app.device, app.commandPool[i], 1, &app.commandBuffers[i]);
    vkDestroyCommandPool(app.device, app.commandPool[i], app.allocator);
    vkDestroyImageView(app.device, app.swapChainImageViews[i], app.allocator);
    vkDestroyFramebuffer(app.device, app.swapChainFramebuffers[i], app.allocator);
  }
  if(app.renderpass) vkDestroyRenderPass(app.device, app.renderpass, app.allocator);
  if(app.swapChain) vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator);
  app.swapChain = null;
}

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
  auto layers = app.queryInstanceLayerProperties();
  auto extensions = app.queryInstanceExtensionProperties();

  if(layers.has("VK_LAYER_KHRONOS_validation")){ app.layers ~= "VK_LAYER_KHRONOS_validation"; }
  if(extensions.has("VK_EXT_debug_report")){ app.instanceExtensions ~= "VK_EXT_debug_report"; }

  VkInstanceCreateInfo createInstance = { 
    sType : VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    enabledLayerCount : cast(uint)app.layers.length,
    ppEnabledLayerNames : &app.layers[0],
    enabledExtensionCount : cast(uint)app.instanceExtensions.length,
    ppEnabledExtensionNames : &app.instanceExtensions[0],
    pApplicationInfo: &app.applicationInfo
  };

  enforceVK(vkCreateInstance(&createInstance, app.allocator, &app.instance));
  SDL_Log("vkCreateInstance[layers:%d, extensions:%d]: %p", app.layers.length, app.instanceExtensions.length, app.instance );

  // Hook instance function
  vkDebugCallback = cast(PFN_vkCreateDebugReportCallbackEXT) vkGetInstanceProcAddr(app.instance, "vkCreateDebugReportCallbackEXT");
  vkDestroyDebugCallback = cast(PFN_vkDestroyDebugReportCallbackEXT) vkGetInstanceProcAddr(app.instance, "vkDestroyDebugReportCallbackEXT");

  // Create Debug callback
  VkDebugReportCallbackCreateInfoEXT createDebug = {
    sType : VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
    flags : VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT | VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT,
    pfnCallback : &debugCallback,
    pUserData : null
  };
  vkDebugCallback(app.instance, &createDebug, app.allocator, &app.debugCallback);

  // Query Physical Devices and pick 0
  auto physicalDevices = app.queryPhysicalDevices();
  app.physicalDevice = physicalDevices[1];

  if(app.queryDeviceExtensionProperties().has("VK_KHR_swapchain")){ app.deviceExtensions ~= "VK_KHR_swapchain"; }

  uint queueFamily = selectQueueFamily(app.physicalDevice);

  // Create Logical Device (with 1 queue)
  float[] queuePriority = [1.0f];
  VkDeviceQueueCreateInfo[] createQueue = [{
    sType : VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    queueFamilyIndex : queueFamily,
    queueCount : 1,
    pQueuePriorities : &queuePriority[0]
  }];

  VkDeviceCreateInfo createDevice = {
    sType : VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    queueCreateInfoCount : cast(uint)createQueue.length,
    pQueueCreateInfos : &createQueue[0],
    enabledExtensionCount : cast(uint)app.deviceExtensions.length,
    ppEnabledExtensionNames : &app.deviceExtensions[0],
  };
  enforceVK(vkCreateDevice(app.physicalDevice, &createDevice, app.allocator, &app.device));
  SDL_Log("vkCreateDevice[extensions:%d]: %p", app.deviceExtensions.length, app.device );

  // Get the Queue
  vkGetDeviceQueue(app.device, queueFamily, 0, &app.queue);
  SDL_Log("vkGetDeviceQueue[family:%d]: %p", queueFamily, app.queue);

  // Create Descriptor Pool
  VkDescriptorPoolSize[] poolSizes = [{
    type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 
    descriptorCount : IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE 
  }];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : 1,
    poolSizeCount : cast(uint32_t)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.descriptorPool);

  //Get a SDL_Vulkan surface
  SDL_Vulkan_CreateSurface(app, app.instance, &app.surface);
  SDL_Log("SDL_Vulkan_CreateSurface: %p", app.surface);

  //Load surface capabilities, and create a swapchain
  app.createOrResizeWindow(queueFamily);

  igCreateContext(null);
  ImGuiIO* io = igGetIO_Nil();
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  igStyleColorsDark(null);
  SDL_Log("ImGuiIO: %p", io);
  ImGui_ImplSDL2_InitForVulkan(app.window);

  ImGui_ImplVulkan_InitInfo imguiInit = {
    Instance : app.instance,
    PhysicalDevice : app.physicalDevice,
    Device : app.device,
    QueueFamily : queueFamily,
    Queue : app.queue,
    PipelineCache : null,
    DescriptorPool : app.descriptorPool,
    Allocator : app.allocator,
    MinImageCount : app.capabilities.minImageCount,
    ImageCount : cast(uint)app.imageCount,
    RenderPass : app.renderpass,
    CheckVkResultFn : &enforceVK
  };
  ImGui_ImplVulkan_Init(&imguiInit);
  SDL_Log("ImGui_ImplVulkan_Init");

  // Main loop
  bool done = false;
  bool demo = true;
  uint nFrames = 5000;
  while (!done && app.totalFramesRendered < nFrames){
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

    int width, height;
    SDL_GetWindowSize(app.window, &width, &height);
    if (width > 0 && height > 0 && (app.rebuild || app.width != width || app.height != height)){
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

void renderFrame(ref App app, ImDrawData* drawData, VkClearValue clear = VkClearValue(VkClearColorValue([0.45f, 0.55f, 0.60f, 1.00f]))){
  VkSemaphore imageAcquired  = app.sync[app.syncIndex].imageAcquired;
  VkSemaphore renderComplete = app.sync[app.syncIndex].renderComplete;

  auto err = vkAcquireNextImageKHR(app.device, app.swapChain, uint.max, imageAcquired, null, &app.frameIndex);
  if (app.verbose) SDL_Log("Frame[%d]: S:%d, F:%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);

  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.frameIndex], true, uint.max));
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.frameIndex]));
  enforceVK(vkResetCommandPool(app.device, app.commandPool[app.frameIndex], 0));

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  enforceVK(vkBeginCommandBuffer(app.commandBuffers[app.frameIndex], &commandBufferInfo));

  int w,h;
  SDL_GetWindowSize(app, &w, &h);
  VkRect2D renderArea = { extent: { width: w, height: h } };

  VkRenderPassBeginInfo renderPassInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass : app.renderpass,
    framebuffer : app.swapChainFramebuffers[app.frameIndex],
    renderArea : renderArea,
    clearValueCount : 1,
    pClearValues : &clear
  };
  vkCmdBeginRenderPass(app.commandBuffers[app.frameIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
  
  ImGui_ImplVulkan_RenderDrawData(drawData, app.commandBuffers[app.frameIndex], null);
  
  vkCmdEndRenderPass(app.commandBuffers[app.frameIndex]);

  enforceVK(vkEndCommandBuffer(app.commandBuffers[app.frameIndex]));
  
  VkCommandBuffer[] submitCommandBuffers = [ app.commandBuffers[app.frameIndex] ];

  VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

  VkSubmitInfo submitInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    waitSemaphoreCount : 1,
    pWaitSemaphores : &imageAcquired,
    pWaitDstStageMask : &waitStage,

    commandBufferCount : cast(uint)submitCommandBuffers.length,
    pCommandBuffers : &submitCommandBuffers[0],
    signalSemaphoreCount : 1,
    pSignalSemaphores : &renderComplete
  };
  
  enforceVK(vkQueueSubmit(app.queue, 1, &submitInfo, app.fences[app.frameIndex]));
}

void presentFrame(ref App app){
  VkSemaphore renderComplete = app.sync[app.syncIndex].renderComplete;
  VkPresentInfoKHR info = {
    sType : VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    waitSemaphoreCount : 1,
    pWaitSemaphores : &renderComplete,
    swapchainCount : 1,
    pSwapchains : &app.swapChain,
    pImageIndices : &app.frameIndex,
  };
  auto err = vkQueuePresentKHR(app.queue, &info);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  app.syncIndex = (app.syncIndex + 1) % app.sync.length; // Now we can use the next set of semaphores
}
