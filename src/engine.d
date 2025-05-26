/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import includes;
public import core.stdc.string : strcmp, memcpy;

import depthbuffer : DepthBuffer;
import camera : Camera;
import compute : Compute, SSBO;
import deletion : CheckedDeletionQueue, DeletionQueue;
import glyphatlas : GlyphAtlas;
import geometry : Geometry, cleanup;
import lights : Light, Lights;
import matrix : multiply, inverse;
import pipeline : GraphicsPipeline;
import images : ColorBuffer;
import imgui : GUI;
import shaders : Shader;
import vector : normalize;
import uniforms : Uniform;
import sync : Sync, Fence;
import sfx : WavFMT;
import textures : Texture;

/** Main application structure
 */
struct App {
  SDL_Window* window;
  alias window this;
  enum const(char)* applicationName = "CalderaD";

  /// Application information structure
  VkApplicationInfo applicationInfo  = {
    pApplicationName: applicationName, 
    applicationVersion: 0, 
    pEngineName: "CalderaD Engine with Dear ImGui", 
    engineVersion: 0,
    apiVersion: VK_MAKE_API_VERSION( 0, 1, 2, 0 )
  };

  VkClearValue[2] clearValue = [ {{ float32: [0.45f, 0.55f, 0.60f, 0.50f] }}, { depthStencil : VkClearDepthStencilValue(1.0f, 0) } ];
  Compute compute;            /// Compute shaders
  Geometry[] objects;         /// All geometric objects for rendering
  Texture[] textures;         /// Textures
  SSBO[] buffers;             /// SSBO buffers
  Light[4] lights = [Lights.White, Lights.Red, Lights.Green, Lights.Blue];
  GUI gui;                    /// ImGui related variables
  Camera camera;              /// Our camera class
  GlyphAtlas glyphAtlas;      /// GlyphAtlas for geometric font rendering

  VkSampler sampler;
  Shader[] shaders;
  VkPipelineShaderStageCreateInfo[] shaderStages;
  VkPipelineShaderStageCreateInfo[] computeStages;
  GraphicsPipeline[VkPrimitiveTopology] pipelines;
  DepthBuffer depthBuffer;
  ColorBuffer colorBuffer;
  DeletionQueue mainDeletionQueue;
  DeletionQueue frameDeletionQueue;
  CheckedDeletionQueue bufferDeletionQueue;
  WavFMT[] soundfx;
  float soundEffectGain = 0.8;

  // ShaderC
  shaderc_compiler_t compiler;
  shaderc_compile_options_t options;

  // SPIR-V reflection
  spvc_context context;

  // Vulkan
  VkInstance instance = null;
  VkPhysicalDevice physicalDevice = null;
  VkPhysicalDeviceProperties properties;
  VkDevice device = null;
  VkQueue queue = null;
  VkDescriptorPool imguiPool = null;
  VkDescriptorSetLayout ImGuiSetLayout = null;

  VkDescriptorPool descriptorPool = null;
  VkDescriptorSetLayout descriptorSetLayout = null;
  VkDescriptorImageInfo[] textureImagesInfo;
  VkDescriptorSet[] descriptorSet = null;

  VkSurfaceKHR surface = null;
  VkSurfaceFormatKHR[] surfaceformats = null;
  VkSwapchainKHR swapChain = null;
  VkCommandPool commandPool = null;
  Uniform uniform = {null, null};

  // per Frame
  Sync[] sync = null;
  Fence[] fences = null;
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
  uint queueFamily = uint.max;          /// Current queueFamily used
  uint syncIndex = 0;                   /// Sync index (Semaphore)
  uint frameIndex = 0;                  /// Current frame index (Fence)
  ulong[4] time = [0, 0, 0, 0];         /// Time monitoring (START, STARTUP, FRAMESTART, LASTTICK)
  uint totalFramesRendered = 0;         /// Total frames rendered so far

  @property uint imageCount() { return(cast(uint)swapChainImages.length); }
  @property uint framesInFlight() { return(cast(uint)swapChainImages.length + 1); }

  const(char)*[] instanceExtensions;    /// Enabled instance extensions
  const(char)*[] deviceExtensions;      /// Enabled device extensions
  const(char)*[] layers;                /// Enabled layers

  // Global boolean flags
  bool finished = false;                /// Is the main loop finished ?
  bool showBounds = true;               /// TO IMPLEMENT: Show bounding boxes
  bool verbose = false;                 /// Be very verbose
  bool rebuild = false;                 /// Rebuild the swapChain?
}

/** Shutdown ImGui and deAllocate all vulkan related objects in existance
 */
void cleanUp(App app){
  enforceVK(vkDeviceWaitIdle(app.device));
  app.frameDeletionQueue.flush(); // Frame deletion queue, flushes the buffers

  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);

  // Delete objects and flush the main deletion queue
  foreach(object; app.objects) { app.cleanup(object); }
  app.mainDeletionQueue.flush();

  // Clear the ShaderC compiler and Quit SDL

  SDL_DestroyWindow(app);
  SDL_Quit();
}

/** Check result of vulkan call and print if an error occured
 */
extern(C) void enforceVK(VkResult err) {
  if (err == VK_SUCCESS) return;
  SDL_Log("[enforceVK] Error: VkResult = %d", err);
  if (err < 0) abort();
}

void enforceSPIRV(App app, spvc_result err){
  if(err == SPVC_SUCCESS) return;
  SDL_Log("[enforceSPIRV] Error: %s", spvc_context_get_last_error_string(app.context));
  abort();
}

/** Log function to allow SDL_Log to be redirected to a file
 */
extern(C) void myLogFn(void* userdata, int category, SDL_LogPriority priority, const char* message) {
  import std.stdio : writefln;
  import std.string : fromStringz;
  writefln("%s", fromStringz(message));
}

