public import includes;
public import core.stdc.string : strcmp;
import sfx : Audio;

struct Sync {
  VkSemaphore imageAcquired;
  VkSemaphore renderComplete;
}

struct App {
  SDL_Window* window;
  alias window this;

  Audio sfx;

  // Application info structure
  VkApplicationInfo applicationInfo  = {
    pApplicationName: "Testing", 
    applicationVersion: 0, 
    pEngineName: "Engine v0", 
    engineVersion: 0,
    apiVersion: VK_MAKE_API_VERSION( 0, 1, 0, 0 )
  };

  VkInstance instance = null;
  VkPhysicalDevice physicalDevice = null;
  VkDevice device = null;
  VkQueue queue = null;
  VkDescriptorPool descriptorPool = null;

  VkSurfaceKHR surface = null;
  VkSurfaceFormatKHR[] surfaceformats = null;
  VkSurfaceCapabilitiesKHR capabilities;
  VkSwapchainKHR swapChain = null;
  VkRenderPass renderpass = null;
  Sync[] sync = null;

  // per Frame
  VkFence[] fences = null;
  VkImage[] swapChainImages = null;
  VkImageView[] swapChainImageViews = null;
  VkCommandPool[] commandPool = null;
  VkCommandBuffer[] commandBuffers = null;
  VkFramebuffer[] swapChainFramebuffers = null;

  VkAllocationCallbacks* allocator = null;
  VkDebugReportCallbackEXT debugCallback = null;

  uint syncIndex = 0;
  uint frameIndex = 0;
  uint totalFramesRendered = 0;

  @property uint width(){ return(capabilities.currentExtent.width); };
  @property uint height(){ return(capabilities.currentExtent.height); };
  @property uint imageCount() { return(cast(uint)swapChainImages.length); }

  const(char)*[] deviceExtensions; // Enabled extensions
  const(char)*[] instanceExtensions; // Enabled extensions
  const(char)*[] layers; // Enabled layers

  bool finished = false;
  bool showdemo = true;
  bool verbose = false;
  bool rebuild = false;
}

extern(C) void enforceVK(VkResult err) {
  if (err == VK_SUCCESS) return;
  SDL_Log("[enforceVK] Error: VkResult = %d\n", err);
  if (err < 0) abort();
}
