/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import phobos;
public import structures;
public import world : World;

enum Stage : string {IMGUI = "IMGUI", COMPUTE = "COMPUTE", RENDER = "RENDER", POST = "POST", SHADOWS = "SHADOWS"};

version(Android){ enum isAndroid = true; }else{ enum isAndroid = false; }

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

  VkClearValue[3] clearValue = [ 
    {{ float32: [0.0f, 0.0f, 0.0f, 1.0f] }}, 
    {{ float32: [0.0f, 0.0f, 0.0f, 1.0f] }}, 
    { depthStencil : VkClearDepthStencilValue(1.0f, 0) } 
  ];
  Compute compute;                                                              /// Compute shaders
  Geometries objects;                                                           /// All geometric objects for rendering
  Bone[string] bones;                                                           /// All animation bones across all objects
  Matrix[] boneOffsets;                                                         /// Animated BoneOffsets for GPU SSBO
  MeshList meshes;                                                              /// Meshes for GPU SSBO
  Textures textures;                                                            /// Textures
  Audio audio;
  WavFMT[] soundfx;                                                             /// Sound effects
  SSBO[string] buffers;                                                         /// SSBO buffers
  UBO[string] ubos;                                                             /// UBO buffers
  Lighting lights = {[Lights.Red, Lights.Green, Lights.Blue, Lights.Bright]};   /// Scene lighting
  GUI gui;                                                                      /// ImGui related variables
  Camera camera;                                                                /// Our camera class
  GlyphAtlas glyphAtlas;                                                        /// GlyphAtlas for geometric font rendering
  TileAtlas tileAtlas;                                                          /// TileAtlas for terrain rendering
  World world;                                                                  /// The game world
  ShadowMap shadows;                                                            /// ShadowMap object

  VkSampler sampler;
  Shader[] shaders;
  Shader[] postProcess;
  GraphicsPipeline[VkPrimitiveTopology] pipelines;
  GraphicsPipeline postProcessPipeline;

  DepthBuffer depthBuffer;
  ImageBuffer offscreenHDR;
  ImageBuffer resolvedHDR;

  // Deletion queues for cleaning up resources
  DeletionQueue mainDeletionQueue;                                              /// On application shutdown
  DeletionQueue swapDeletionQueue;                                              /// When rebuilding the SwapChain
  CheckedDeletionQueue bufferDeletionQueue;                                     /// On each frame rendered

  // ShaderC & SPIR-V reflection
  shaderc_compiler_t compiler;                                                  /// ShaderC compiler
  shaderc_compile_options_t options;                                            /// ShaderC compiler options
  IncluderContext includeContext;                                               /// ShaderC compiler includes
  spvc_context context;                                                         /// SpirV context

  // Vulkan Instance related variables
  VkInstance instance = null;
  SupportedFeatures supported;
  VkPhysicalDevice[] physicalDevices;

  VkDevice device = null;
  VkQueue queue = null;                                                         /// Render Queue
  VkQueue transfer = null;                                                      /// Transfer Queue

  VkDescriptorPool[string] pools;                                               /// Descriptor pools (IMGUI, COMPUTE, RENDER)
  VkDescriptorSetLayout[string] layouts;                                        /// Descriptor layouts (IMGUI, RENDER, N x computeShader.PATH)
  VkDescriptorSet[][string] sets;                                               /// Descriptor sets per Frames In Flight for (IMGUI, RENDER, N x computeShader.PATH)

  // Surface, Formats, SwapChain, and commandpool resources
  VkSurfaceKHR surface = null;                                                  /// Vulkan Surface
  VkSurfaceFormatKHR[] surfaceformats = null;                                   /// Available Surface formats
  VkFormat colorFormat;
  uint format = 0;                                                              /// selected format
  VkSwapchainKHR swapChain = null;                                              /// Our SwapChain
  VkCommandPool commandPool = null;                                             /// Our Rendering Command Pool
  VkCommandPool transferPool = null;                                            /// Our Texture Transfer Pool

  // Per frame resources (reset when rebuilding the swapchain)
  Sync[] sync = null;
  VkSemaphore[] renderComplete;
  Fence[] fences = null;
  VkImage[] swapChainImages = null;
  VkImageView[] swapChainImageViews = null;
  RenderPass scenePass;                                                         /// Scene renderpass + framebuffers + commands
  RenderPass postPass;                                                          /// Post-process renderpass + framebuffers + commands
  RenderPass imguiPass;                                                         /// ImGui renderpass + framebuffers + commands

  VkAllocationCallbacks* allocator = null;
  VkDebugReportCallbackEXT debugCallback = null;

  Threading concurrency;

  // Sync and Frame Tracking
  uint selectedDevice = 0;
  uint queueFamily = uint.max;                                                  /// Current GFX queueFamily used
  uint syncIndex = 0;                                                           /// Sync index (Semaphore)
  uint frameIndex = 0;                                                          /// Current frame index (Fence)
  float soundEffectGain = 0.8;                                                  /// Sound Effects Gain
  ulong[5] time = [0, 0, 0, 0, 0];                                              /// Time monitoring (START, STARTUP, FRAMESTART, FRAMESTOP, LASTTICK)
  uint totalFramesRendered = 0;                                                 /// Total frames rendered so far

  const(char)*[] instanceExtensions;                                            /// Enabled instance extensions
  const(char)*[] deviceExtensions;                                              /// Enabled device extensions
  const(char)*[] layers;                                                        /// Enabled layers

  // Global boolean flags
  bool finished = false;                                                        /// Is the main loop finished ?
  bool showBounds = true;                                                       /// Show bounding boxes
  bool showShadows = !isAndroid;                                                /// Allow shadows to be disabled
  bool showRays = false;                                                        /// Show rays
  bool hasCompute = true;
  uint verbose = 0;                                                             /// Be very verbose
  bool disco = false;                                                           /// Disco mode
  bool rebuild = false;                                                         /// Rebuild the swapChain?
  bool isMinimized = false;                                                     /// isMinimized?
  bool isImGuiInitialized = false;                                              /// ImGui flag, needed for Android

  // Properties based on the SwapChain
  @property pure @nogc uint imageCount() nothrow { return(cast(uint)swapChainImages.length); }
  @property pure @nogc bool trace() nothrow { return(verbose > 1); }
  @property pure @nogc uint framesInFlight() nothrow { return(cast(uint)swapChainImages.length + 1); }
  @property pure @nogc VkPhysicalDevice physicalDevice() nothrow { return(physicalDevices[selectedDevice]); }
  @property VkPhysicalDeviceProperties properties() {
    VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(physicalDevice(), &p); return(p);
  }
}

/** Check result of Vulkan call and print if an error occured
 */
extern(C) void enforceVK(VkResult err) {
  if (err == VK_SUCCESS) return;
  SDL_Log("[enforceVK] Error: VkResult = %d", err);
  if (err < 0) abort();
}

/** Check result of SpirV-Compiler call and print if an error occured
 */
void enforceSPIRV(App app, spvc_result err) {
  if(err == SPVC_SUCCESS) return;
  SDL_Log("[enforceSPIRV] Error: %s", spvc_context_get_last_error_string(app.context));
  abort();
}

