public import includes;
public import core.stdc.string : strcmp;

import geometry : Geometry, Cube;

struct Sync {
  VkSemaphore imageAcquired;
  VkSemaphore renderComplete;
}

struct GraphicsPipeline {
  VkPipelineLayout pipelineLayout;
  VkPipeline graphicsPipeline;
}

struct DepthBuffer {
  VkImage depthImage;
  VkDeviceMemory depthImageMemory;
  VkImageView depthImageView;
}

struct App {
  SDL_Window* window;
  alias window this;
  enum const(char)* applicationName = "CalderaD";

  // Application info structure
  VkApplicationInfo applicationInfo  = {
    pApplicationName: applicationName, 
    applicationVersion: 0, 
    pEngineName: "CalderaD Engine with Dear ImGui", 
    engineVersion: 0,
    apiVersion: VK_MAKE_API_VERSION( 0, 1, 0, 0 )
  };

  VkClearValue[2] clear = [ {{ float32: [0.45f, 0.55f, 0.60f, 0.50f] }}, { depthStencil : VkClearDepthStencilValue(1.0f, 0) } ];
  Geometry[] objects = [Cube()];
  GraphicsPipeline pipeline = {null, null};
  DepthBuffer depthbuffer = {null, null, null};

  // Vulkan
  VkInstance instance = null;
  VkPhysicalDevice physicalDevice = null;
  VkDevice device = null;
  VkQueue queue = null;
  VkDescriptorPool descriptorPool = null;

  VkSurfaceKHR surface = null;
  VkSurfaceFormatKHR[] surfaceformats = null;
  VkSurfaceCapabilitiesKHR capabilities;
  VkSwapchainKHR swapChain = null;
  VkCommandPool commandPool = null;
  Sync[] sync = null;

  // per Frame
  VkFence[] fences = null;
  VkImage[] swapChainImages = null;
  VkRenderPass imguiPass = null;
  VkRenderPass renderpass = null;
  VkImageView[] swapChainImageViews = null;
  VkCommandBuffer[] imguiBuffers = null;
  VkCommandBuffer[] renderBuffers = null;
  VkFramebuffer[] swapChainFramebuffers = null;

  VkAllocationCallbacks* allocator = null;
  VkDebugReportCallbackEXT debugCallback = null;

  // Sync and Frame Tracking
  uint queueFamily = uint.max;
  uint syncIndex = 0;
  uint frameIndex = 0;
  uint totalFramesRendered = 0;

  @property uint width(){ return(capabilities.currentExtent.width); };
  @property uint height(){ return(capabilities.currentExtent.height); };
  @property uint imageCount() { return(cast(uint)swapChainImages.length); }
  /*@property VkClearValue[2] clear() { 

    clearValues[0].color = VkClearColorValue([0.0f, 0.0f, 0.0f, 1.0f]);
    clearValues[1].depthStencil = VkClearDepthStencilValue(1.0f, 0);
    return(clearValues);
  }*/

  const(char)*[] instanceExtensions;    // Enabled instance extensions
  const(char)*[] deviceExtensions;      // Enabled device extensions
  const(char)*[] layers;                // Enabled layers

  // Global boolean flags
  bool finished = false;
  bool showdemo = true;
  bool verbose = true;
  bool rebuild = false;
}

extern(C) void enforceVK(VkResult err) {
  if (err == VK_SUCCESS) return;
  SDL_Log("[enforceVK] Error: VkResult = %d\n", err);
  if (err < 0) abort();
}
