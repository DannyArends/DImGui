/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import includes;
public import core.stdc.string : strcmp, memcpy;

import validation;

import camera : Camera;
import glyphatlas : GlyphAtlas;
import geometry : Geometry, deAllocate;
import matrix : multiply, inverse;
import vector : normalize;
import uniforms : Uniform;
import textures : Texture, deAllocate;
import window : destroyFrameData;

/** Sync
 */
struct Sync {
  VkSemaphore imageAcquired;
  VkSemaphore renderComplete;
}

/** GraphicsPipeline
 */
struct GraphicsPipeline {
  VkPipelineLayout pipelineLayout;
  VkPipeline graphicsPipeline;
}

/** DepthBuffer
 */
struct DepthBuffer {
  VkImage depthImage;
  VkDeviceMemory depthImageMemory;
  VkImageView depthImageView;
}

/** Main application structure
 */
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
    apiVersion: VK_MAKE_API_VERSION( 0, 1, 2, 0 )
  };

  VkClearValue[2] clearValue = [ {{ float32: [0.45f, 0.55f, 0.60f, 0.50f] }}, { depthStencil : VkClearDepthStencilValue(1.0f, 0) } ];
  Geometry[] objects;
  Texture[] textures;
  VkSampler sampler;
  Camera camera;
  GlyphAtlas glyphAtlas;
  VkShaderModule[] shaders;
  VkPipelineShaderStageCreateInfo[] shaderStages;
  GraphicsPipeline[VkPrimitiveTopology] pipelines;
  DepthBuffer depthBuffer;
  ImGuiIO* io;

  // Vulkan
  VkInstance instance = null;
  VkPhysicalDevice physicalDevice = null;
  VkPhysicalDeviceProperties properties;
  VkDevice device = null;
  VkQueue queue = null;
  VkDescriptorPool imguiPool = null;
  VkDescriptorPool descriptorPool = null;
  VkDescriptorSetLayout descriptorSetLayout = null;
  VkDescriptorSet descriptorSet = null;

  VkSurfaceKHR surface = null;
  VkSurfaceFormatKHR[] surfaceformats = null;
  VkSwapchainKHR swapChain = null;
  VkCommandPool commandPool = null;
  Sync[] sync = null;
  Uniform uniform = {null, null};

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

  @property uint imageCount() { return(cast(uint)swapChainImages.length); }

  const(char)*[] instanceExtensions;    // Enabled instance extensions
  const(char)*[] deviceExtensions;      // Enabled device extensions
  const(char)*[] layers;                // Enabled layers

  // Global boolean flags
  bool finished = false;
  bool showdemo = false;
  bool showBounds = true;
  bool verbose = false;
  bool rebuild = false;
}

void cleanUp(App app){
  enforceVK(vkDeviceWaitIdle(app.device));
  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);
  app.destroyFrameData();

  foreach(shader; app.shaders){  vkDestroyShaderModule(app.device, shader, app.allocator); }
  vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator);
  vkDestroyDescriptorPool(app.device, app.imguiPool, app.allocator);
  foreach(object; app.objects) { app.deAllocate(object); }
  foreach(texture; app.textures) { app.deAllocate(texture); }
  vkDestroySampler(app.device, app.sampler, null);
  vkDestroyCommandPool(app.device, app.commandPool, app.allocator);
  vkDestroyDebugCallback(app.instance, app.debugCallback, app.allocator);
  vkDestroyDevice(app.device, app.allocator);

  vkDestroySurfaceKHR(app.instance, app.surface, app.allocator);
  vkDestroyInstance(app.instance, app.allocator);

  SDL_DestroyWindow(app);
  SDL_Quit();
}

extern(C) void enforceVK(VkResult err) {
  if (err == VK_SUCCESS) return;
  SDL_Log("[enforceVK] Error: VkResult = %d\n", err);
  if (err < 0) abort();
}

