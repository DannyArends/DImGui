import includes;

struct App {
  SDL_Window*                 ptr = null;
  alias ptr this;

  // Application info structure
  VkApplicationInfo applicationInfo  = {
    pApplicationName: "DImgUi", 
    applicationVersion: 0, 
    pEngineName: "DImgUi v0", 
    engineVersion: 0,
    apiVersion: VK_MAKE_API_VERSION( 0, 1, 4, 0 )
  };

  VkAllocationCallbacks*      g_Allocator = null;
  VkInstance                  instance = null;

  uint                        nPhysDevices;
  uint                        selected;
  VkPhysicalDevice[]          physicalDevices;
  @property VkPhysicalDevice  physicalDevice() { return(physicalDevices[selected]); }

  VkDevice                    g_Device = null;
  uint32_t                    g_QueueFamily = uint.max;
  VkQueue                     g_Queue = null;
  VkDebugReportCallbackEXT    g_DebugReport = null;
  VkPipelineCache             g_PipelineCache = null;
  VkDescriptorPool            g_DescriptorPool = null;

  ImGui_ImplVulkanH_Window    g_Window;
  uint32_t                    g_MinImageCount = 2;
  bool                        g_SwapChainRebuild = false;
}

