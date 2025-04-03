import includes;

import camera : Camera;
import descriptorset : Descriptor;
import surface : Surface;
import logicaldevice : VkQueueFamilyIndices;
import swapchain : SwapChain;
import pipeline : GraphicsPipeline;
import geometry : Geometry;

import texture : Texture;
import uniformbuffer : Uniform;

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
  VkCommandPool                         commandPool;
  VkCommandBuffer[]                     commandBuffers;
  SwapChain                             swapchain;
  VkRenderPass                          renderpass;
  GraphicsPipeline                      pipeline;
  Geometry[]                            geometry;
  Descriptor                            descriptor;
  Texture[] textureArray;
  VkSampler textureSampler;
  Uniform uniform;
  Camera camera;

  ImGui_ImplVulkanH_Window*             window;

  @property ImGui_ImplVulkanH_Window*   wd() { return(window); }
  @property VkPhysicalDevice            physicalDevice() { return(physicalDevices[selected]); }
  @property uint                        queueFamily() { return(familyIndices.graphicsFamily); }
  @property uint                        minImageCnt(){ return(surface.capabilities.minImageCount); }
  @property float                       aspectRatio(){
    return(surface.capabilities.currentExtent.width / cast(float) surface.capabilities.currentExtent.height);
  }

  bool                                  rebuildSwapChain = false;
  bool                                  verbose = false;
}


