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

  VkAllocationCallbacks*                allocator = null;
  VkInstance                            instance = null;

  uint32_t                              nProperties;
  VkExtensionProperties[]               properties;

  uint32_t                              nExtensions;
  const(char)*[]                        extensions;
  const(char)*[]                        validationLayers;

  uint                                  nPhysDevices;
  uint                                  selected;
  VkPhysicalDevice[]                    physicalDevices;
  @property VkPhysicalDevice            physicalDevice() { return(physicalDevices[selected]); }


  VkDevice                              dev = null;
  uint32_t                              queueFamily = uint.max;
  VkQueue                               queue = null;
  VkDebugReportCallbackEXT              debugReport = null;
  VkPipelineCache                       pipelineCache = null;
  VkDescriptorPool                      descriptorPool = null;

  ImGui_ImplVulkanH_Window*             window;
  @property ImGui_ImplVulkanH_Window*   wd() { return(window); }

  uint32_t                              minImageCnt = 2;
  bool                                  rebuildSwapChain = false;
  bool                                  verbose = false;
}

