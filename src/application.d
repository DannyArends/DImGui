import includes;

import surface : Surface;
import logicaldevice : VkQueueFamilyIndices;

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
  VkExtensionProperties[]               properties;
  const(char)*[]                        extensions;
  const(char)*[]                        validationLayers;
  uint                                  selected;
  VkPhysicalDevice[]                    physicalDevices;


  VkDevice                              dev = null;
  Surface                               surface;
  VkQueueFamilyIndices                  familyIndices;
  VkQueue                               gfxQueue = null;
  VkQueue                               presentQueue = null;
  VkDebugReportCallbackEXT              debugReport = null;
  VkPipelineCache                       pipelineCache = null;
  VkDescriptorPool                      descriptorPool = null;

  ImGui_ImplVulkanH_Window*             window;

  @property ImGui_ImplVulkanH_Window*   wd() { return(window); }
  @property VkPhysicalDevice            physicalDevice() { return(physicalDevices[selected]); }
  @property uint32_t                    queueFamily() { return(familyIndices.graphicsFamily); }

  uint                                  minImageCnt = 2;
  bool                                  rebuildSwapChain = false;
  bool                                  verbose = false;
}

