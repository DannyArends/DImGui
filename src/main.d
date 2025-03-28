import includes;
import std.string : toStringz;
import core.stdc.string : strcmp;

static VkAllocationCallbacks*   g_Allocator = null;
static VkInstance               g_Instance = cast(VkInstance)VK_NULL_HANDLE;
static VkPhysicalDevice         g_PhysicalDevice = cast(VkPhysicalDevice)VK_NULL_HANDLE;
static VkDevice                 g_Device = cast(VkDevice)VK_NULL_HANDLE;
static uint32_t                 g_QueueFamily = uint.max;
static VkQueue                  g_Queue = cast(VkQueue)VK_NULL_HANDLE;
static VkDebugReportCallbackEXT g_DebugReport = cast(VkDebugReportCallbackEXT)VK_NULL_HANDLE;
static VkPipelineCache          g_PipelineCache = cast(VkPipelineCache)VK_NULL_HANDLE;
static VkDescriptorPool         g_DescriptorPool = cast(VkDescriptorPool)VK_NULL_HANDLE;

static ImGui_ImplVulkanH_Window g_Window;
static uint32_t                 g_MinImageCount = 2;
static bool                     g_SwapChainRebuild = false;

PFN_vkCreateDebugReportCallbackEXT  vkDebugCallback;
PFN_vkDestroyDebugReportCallbackEXT vkDestroyDebugCallback;

extern(C) void enforceVK(VkResult err) {
  if (err == VK_SUCCESS) return;
  SDL_Log("[vulkan] Error: VkResult = %d\n", err);
  if (err < 0) abort();
}

extern(C) uint debugCallback(VkDebugReportFlagsEXT flags, VkDebugReportObjectTypeEXT objectType, uint64_t object, 
                            size_t location, int32_t messageCode, const char* pLayerPrefix, const char* pMessage, void* pUserData) {
    SDL_Log("[vulkan] Debug report from ObjectType: %i\nMessage: %s\n\n", objectType, pMessage);
    return VK_FALSE;
}

bool IsExtensionAvailable(VkExtensionProperties[] properties, const(char)* extension) {
  for(uint32_t i = 0 ; i < properties.length; i++) {
    if (strcmp(toStringz(properties[i].extensionName), extension) == 0) return true;
  }
  return false;
}

void SetupVulkan(const(char)*[] extensions) {
  // Enumerate available extensions
  uint32_t properties_count;
  VkExtensionProperties[] properties;
  vkEnumerateInstanceExtensionProperties(null, &properties_count, null);
  properties.length = properties_count;
  enforceVK(vkEnumerateInstanceExtensionProperties(null, &properties_count, &properties[0]));

  // Enable required extensions
  if (IsExtensionAvailable(properties, toStringz(VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME))){
    extensions.length += 1;
    extensions[extensions.length-1] = toStringz(VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
  }

  // Add Debug layer
  const(char)*[] layers = ["VK_LAYER_KHRONOS_validation"];

  extensions.length += 1;
  extensions[extensions.length-1] = "VK_EXT_debug_report";

  // Create instance
  VkInstanceCreateInfo createInstance = { 
    sType : VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    enabledLayerCount : 1,
    ppEnabledLayerNames : &layers[0],
    enabledExtensionCount : cast(uint)extensions.length,
    ppEnabledExtensionNames : &extensions[0]
  };

  vkCreateInstance(&createInstance, g_Allocator, &g_Instance);
  SDL_Log("vkCreateInstance: %p", g_Instance);

  // Hook instance function
  vkDebugCallback = cast(PFN_vkCreateDebugReportCallbackEXT) vkGetInstanceProcAddr(g_Instance, "vkCreateDebugReportCallbackEXT");
  vkDestroyDebugCallback = cast(PFN_vkDestroyDebugReportCallbackEXT) vkGetInstanceProcAddr(g_Instance, "vkDestroyDebugReportCallbackEXT");

  VkDebugReportCallbackCreateInfoEXT createDebug = {
    sType : VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
    flags : VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT | VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT,
    pfnCallback : &debugCallback,
    pUserData : null
  };
  vkDebugCallback(g_Instance, &createDebug, g_Allocator, &g_DebugReport);

  // Select Physical Device (GPU)
  g_PhysicalDevice = ImGui_ImplVulkanH_SelectPhysicalDevice(g_Instance);

  //  Select graphics queue family
  g_QueueFamily = ImGui_ImplVulkanH_SelectQueueFamilyIndex(g_PhysicalDevice);

  uint32_t device_extensions_count = 1;
  const(char)*[] device_extensions = ["VK_KHR_swapchain"];

  // Create Logical Device (with 1 queue)
  float[] queue_priority = [1.0f];
  VkDeviceQueueCreateInfo[1] queue_info;
  queue_info[0].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  queue_info[0].queueFamilyIndex = g_QueueFamily;
  queue_info[0].queueCount = 1;
  queue_info[0].pQueuePriorities = &queue_priority[0];

  VkDeviceCreateInfo createDevice = {
    sType : VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    queueCreateInfoCount : queue_info.sizeof / queue_info[0].sizeof,
    pQueueCreateInfos : &queue_info[0],
    enabledExtensionCount : device_extensions_count,
    ppEnabledExtensionNames : &device_extensions[0],
  };
  vkCreateDevice(g_PhysicalDevice, &createDevice, g_Allocator, &g_Device);

  vkGetDeviceQueue(g_Device, g_QueueFamily, 0, &g_Queue);

  // Create Descriptor Pool
  VkDescriptorPoolSize[] pool_sizes = [ { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE } ];
  uint maxSets = 0;
  for(int i = 0; i < pool_sizes.length; i++){
      VkDescriptorPoolSize pool_size = pool_sizes[i];
      maxSets += pool_size.descriptorCount;
  }

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : maxSets,
    poolSizeCount : cast(uint32_t)pool_sizes.length,
    pPoolSizes : &pool_sizes[0]
  };
  vkCreateDescriptorPool(g_Device, &createPool, g_Allocator, &g_DescriptorPool);
}

static void SetupVulkanWindow(ImGui_ImplVulkanH_Window* wd, VkSurfaceKHR surface, int width, int height) {
  wd.Surface = surface;

  // Check for WSI support
  VkBool32 isSupported;
  vkGetPhysicalDeviceSurfaceSupportKHR(g_PhysicalDevice, g_QueueFamily, wd.Surface, &isSupported);
  if (!isSupported) {
    SDL_Log("[vulkan] Error no WSI support on physical device 0");
    abort();
  }

  // Select Image & ColorSpace Format
  VkFormat[] rImageFormat = [ VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8_UNORM, VK_FORMAT_R8G8B8_UNORM ];
  VkColorSpaceKHR rColorSpace = VK_COLORSPACE_SRGB_NONLINEAR_KHR;
  wd.SurfaceFormat = ImGui_ImplVulkanH_SelectSurfaceFormat(g_PhysicalDevice, wd.Surface, &rImageFormat[0], cast(int)rImageFormat.length, rColorSpace);

  // Select presentMode
  VkPresentModeKHR[] presentModes = [ VK_PRESENT_MODE_FIFO_KHR ];
  //VkPresentModeKHR[] presentModes = [ VK_PRESENT_MODE_MAILBOX_KHR, VK_PRESENT_MODE_IMMEDIATE_KHR, VK_PRESENT_MODE_FIFO_KHR ];
  wd.PresentMode = ImGui_ImplVulkanH_SelectPresentMode(g_PhysicalDevice, wd.Surface, &presentModes[0], cast(int)presentModes.length);

  // Create ImGUI window
  ImGui_ImplVulkanH_CreateOrResizeWindow(g_Instance, g_PhysicalDevice, g_Device, wd, g_QueueFamily, g_Allocator, width, height, g_MinImageCount);
}

static void FrameRender(ImGui_ImplVulkanH_Window* wd, ImDrawData* drawData) {
  VkSemaphore image_acquired_semaphore  = wd.FrameSemaphores.Data[wd.SemaphoreIndex].ImageAcquiredSemaphore;
  VkSemaphore render_complete_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].RenderCompleteSemaphore;
  VkResult err = vkAcquireNextImageKHR(g_Device, wd.Swapchain, uint64_t.max, image_acquired_semaphore, cast(VkFence_T*)VK_NULL_HANDLE, &wd.FrameIndex);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) g_SwapChainRebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);

  ImGui_ImplVulkanH_Frame* fd = &wd.Frames.Data[wd.FrameIndex];

  {  // Wait for Fence
    enforceVK(vkWaitForFences(g_Device, 1, &fd.Fence, VK_TRUE, uint64_t.max));
    enforceVK(vkResetFences(g_Device, 1, &fd.Fence));
  }

  {  // Record command buffer
    enforceVK(vkResetCommandPool(g_Device, fd.CommandPool, 0));
    VkCommandBufferBeginInfo info = {
      sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
    };
    enforceVK(vkBeginCommandBuffer(fd.CommandBuffer, &info));
  }

  {  // RenderPass
    VkRect2D renderArea = { extent: { width: wd.Width, height: wd.Height } };

    VkRenderPassBeginInfo info = {
      sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      renderPass : wd.RenderPass,
      framebuffer : fd.Framebuffer,
      renderArea : renderArea,
      clearValueCount : 1,
      pClearValues : &wd.ClearValue
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
    enforceVK(vkQueueSubmit(g_Queue, 1, &info, fd.Fence));
  }
}

void FramePresent(ImGui_ImplVulkanH_Window* wd) {
  if (g_SwapChainRebuild) return;
  VkSemaphore render_complete_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].RenderCompleteSemaphore;
  VkPresentInfoKHR info = {
    sType : VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    waitSemaphoreCount : 1,
    pWaitSemaphores : &render_complete_semaphore,
    swapchainCount : 1,
    pSwapchains : &wd.Swapchain,
    pImageIndices : &wd.FrameIndex,
  };
  VkResult err = vkQueuePresentKHR(g_Queue, &info);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) g_SwapChainRebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  wd.SemaphoreIndex = (wd.SemaphoreIndex + 1) % wd.SemaphoreCount; // Now we can use the next set of semaphores
}

void main(string[] args){
  auto g_Window = *ImGui_ImplVulkanH_Window_ImGui_ImplVulkanH_Window();

  // Setup SDL
  SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER);
  SDL_version compiled;
  SDL_version linked;

  SDL_GetVersion(&linked);
  SDL_Log("We compiled against SDL version %u.%u.%u ...\n", SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_PATCHLEVEL);
  SDL_Log("But we are linking against SDL version %u.%u.%u.\n", linked.major, linked.minor, linked.patch);

  SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
  SDL_Window* window = SDL_CreateWindow("ImGUI", SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), 1280, 720, window_flags);

  // Get available extensions
  uint32_t extensions_count = 0;
  const(char)*[] extensions;
  SDL_Vulkan_GetInstanceExtensions(window, &extensions_count, null);
  extensions.length = extensions_count;
  SDL_Vulkan_GetInstanceExtensions(window, &extensions_count, &extensions[0]);
  // Setup Vulkan
  SetupVulkan(extensions);

  // Create Window Surface
  VkSurfaceKHR surface;
  SDL_Vulkan_CreateSurface(window, g_Instance, &surface);
  SDL_Log("SDL_Vulkan_CreateSurface: %p", surface);

  int w, h;
  SDL_GetWindowSize(window, &w, &h);
  SetupVulkanWindow(&g_Window, surface, w, h);

  igCreateContext(null);
  ImGuiIO* io = igGetIO_Nil(); cast(void)io;
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
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
  ImGui_ImplSDL2_InitForVulkan(window);
  ImGui_ImplVulkan_InitInfo init_info = {
    Instance : g_Instance,
    PhysicalDevice : g_PhysicalDevice,
    Device : g_Device,
    QueueFamily : g_QueueFamily,
    Queue : g_Queue,
    PipelineCache : g_PipelineCache,
    DescriptorPool : g_DescriptorPool,
    RenderPass : g_Window.RenderPass,
    Subpass : 0,
    MinImageCount : g_MinImageCount,
    ImageCount : g_Window.ImageCount,
    MSAASamples : VK_SAMPLE_COUNT_1_BIT,
    Allocator : g_Allocator,
    CheckVkResultFn : &enforceVK
  };
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
      if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_CLOSE && event.window.windowID == SDL_GetWindowID(window)) done = true;
    }
    if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) {
      SDL_Delay(10);
      continue;
    }
    SDL_GetWindowSize(window, &w, &h);
    if (w > 0 && h > 0 && (g_SwapChainRebuild || g_Window.Width != w || g_Window.Height != h)) {
      ImGui_ImplVulkan_SetMinImageCount(g_MinImageCount);
      ImGui_ImplVulkanH_CreateOrResizeWindow(g_Instance, g_PhysicalDevice, g_Device, &g_Window, g_QueueFamily, g_Allocator, w, h, g_MinImageCount);
      g_Window.FrameIndex = 0;
      g_SwapChainRebuild = false;
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
    g_Window.ClearValue.color.float32 = [clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w];

    // Render a frame
    if (!main_is_minimized) FrameRender(&g_Window, drawData);

    // Update and render additional Platform windows
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
      igUpdatePlatformWindows();
      igRenderPlatformWindowsDefault(null, null);
    }

    // Present frame
    if (!main_is_minimized) FramePresent(&g_Window);
  }

  // Cleanup
  enforceVK(vkDeviceWaitIdle(g_Device));
  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);
  ImGui_ImplVulkanH_DestroyWindow(g_Instance, g_Device, &g_Window, g_Allocator);

  vkDestroyDescriptorPool(g_Device, g_DescriptorPool, g_Allocator);
  vkDestroyDebugCallback(g_Instance, g_DebugReport, g_Allocator);
  vkDestroyDevice(g_Device, g_Allocator);
  vkDestroyInstance(g_Instance, g_Allocator);

  SDL_DestroyWindow(window);
  SDL_Quit();
  return;
}

