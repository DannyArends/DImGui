import includes;

struct App {
  SDL_Window*              window = null;

  VkAllocationCallbacks*   g_Allocator = null;
  VkInstance               g_Instance = cast(VkInstance)VK_NULL_HANDLE;
  VkPhysicalDevice         g_PhysicalDevice = cast(VkPhysicalDevice)VK_NULL_HANDLE;
  VkDevice                 g_Device = cast(VkDevice)VK_NULL_HANDLE;
  uint32_t                 g_QueueFamily = uint.max;
  VkQueue                  g_Queue = cast(VkQueue)VK_NULL_HANDLE;
  VkDebugReportCallbackEXT g_DebugReport = cast(VkDebugReportCallbackEXT)VK_NULL_HANDLE;
  VkPipelineCache          g_PipelineCache = cast(VkPipelineCache)VK_NULL_HANDLE;
  VkDescriptorPool         g_DescriptorPool = cast(VkDescriptorPool)VK_NULL_HANDLE;

  ImGui_ImplVulkanH_Window g_Window;
  uint32_t                 g_MinImageCount = 2;
  bool                     g_SwapChainRebuild = false;
}

