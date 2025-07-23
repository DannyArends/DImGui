/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import includes;

public import core.memory : GC;
public import core.stdc.string : strcmp, memcpy, strstr;
public import core.time : MonoTime, dur;
public import core.thread : Thread, thread_joinAll;
public import core.sync.mutex : Mutex;

public import std.algorithm : filter, map, min, remove, reverse, sort, swap;
public import std.array : array, split;
public import std.concurrency : Tid, send, spawn, thisTid, receive, receiveTimeout;
public import std.conv : to;
public import std.format : format;
public import std.file : exists, isFile, isDir, dirEntries, SpanMode;
public import std.math : abs, ceil, sqrt, PI, cos, sin, tan, acos, asin, atan, atan2, fmod, isFinite, isNaN;
public import std.path : baseName, dirName, extension, globMatch, stripExtension;
public import std.random : Random, uniform;
public import std.regex : regex, matchAll;
public import std.string : toStringz, fromStringz, lastIndexOf, indexOf, startsWith, strip, chomp, splitLines;
public import std.traits : EnumMembers;
public import std.utf : isValidDchar;

import animation : Animation;
import bone : Bone;
import camera : Camera;
import compute : Compute;
import depthbuffer : DepthBuffer;
import deletion : CheckedDeletionQueue, DeletionQueue;
import framebuffer : FrameBuffer;
import glyphatlas : GlyphAtlas;
import geometry : Geometries, cleanup;
import images : ImageBuffer;
import imgui : GUI, saveSettings;
import lights : Lighting, Lights;
import matrix : Matrix, multiply, inverse;
import mesh : Mesh;
import node : Node;
import pipeline : GraphicsPipeline;
import shaders : Shader, IncluderContext;
import uniforms : UBO;
import sync : Sync, Fence;
import ssbo : SSBO;
import shadow : ShadowMap;
import sfx : WavFMT;
import textures : Textures;

const(char)* IMGUI = "IMGUI"; 
const(char)* COMPUTE = "COMPUTE";
const(char)* RENDER = "RENDER";
const(char)* POST = "POST";
const(char)* SHADOWS = "SHADOWS";

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
  Mesh[] meshInfo;                                                              /// Meshes for GPU SSBO
  Textures textures;                                                            /// Textures
  WavFMT[] soundfx;                                                             /// Sound effects
  SSBO[string] buffers;                                                         /// SSBO buffers
  UBO[string] ubos;                                                             /// UBO buffers
  Lighting lights = {[Lights.Red, Lights.Green, Lights.Blue, Lights.Bright]};   /// Scene lighting
  GUI gui;                                                                      /// ImGui related variables
  Camera camera;                                                                /// Our camera class
  GlyphAtlas glyphAtlas;                                                        /// GlyphAtlas for geometric font rendering
  ShadowMap shadows;

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
  DeletionQueue frameDeletionQueue;                                             /// When rebuilding the SwapChain
  CheckedDeletionQueue bufferDeletionQueue;                                     /// On each frame rendered

  // ShaderC & SPIR-V reflection
  shaderc_compiler_t compiler;                                                  /// ShaderC compiler
  shaderc_compile_options_t options;                                            /// ShaderC compiler options
  IncluderContext includeContext;
  spvc_context context;                                                         /// SpirV context

  // Vulkan Instance related variables
  VkInstance instance = null;
  VkPhysicalDevice physicalDevice = null;
  VkPhysicalDeviceProperties properties;
  VkDevice device = null;
  VkQueue queue = null;                                                         /// Render Queue
  VkQueue transfer = null;                                                      /// Transfer Queue

  VkDescriptorPool[const(char)*] pools;                                         /// Descriptor pools (IMGUI, COMPUTE, RENDER)
  VkDescriptorSetLayout[const(char)*] layouts;                                  /// Descriptor layouts (IMGUI, RENDER, N x computeShader.PATH)
  VkDescriptorSet[][const(char)*] sets;                                         /// Descriptor sets per Frames In Flight for (IMGUI, RENDER, N x computeShader.PATH)

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
  Fence[] fences = null;
  VkImage[] swapChainImages = null;
  VkImageView[] swapChainImageViews = null;
  FrameBuffer framebuffers;

  VkRenderPass imgui = null;                                                    /// ImGui renderpass
  VkRenderPass scene = null;                                                    /// Main scene renderpass
  VkRenderPass postprocess = null;                                              /// Post-processing renderpass

  VkCommandBuffer[] imguiBuffers = null;
  VkCommandBuffer[] renderBuffers = null;
  VkCommandBuffer[] shadowBuffers = null;

  VkAllocationCallbacks* allocator = null;
  VkDebugReportCallbackEXT debugCallback = null;

  // Sync and Frame Tracking
  uint queueFamily = uint.max;                                                  /// Current queueFamily used
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
  bool showBounds = true;                                                      /// Show bounding boxes
  bool showShadows = false;                                                     /// TODO: Allow shadows to be disabled
  bool showRays = false;                                                        /// Show rays
  uint verbose = 0;                                                             /// Be very verbose
  bool disco = false;                                                           /// Disco mode
  bool rebuild = false;                                                         /// Rebuild the swapChain?
  bool isMinimized = false;                                                     /// isMinimized?
  bool isImGuiInitialized = false;
  // Properties based on the SwapChain
  @property pure @nogc uint imageCount() nothrow { return(cast(uint)swapChainImages.length); }
  @property pure @nogc bool trace() nothrow { return(verbose > 1); }
  @property pure @nogc uint framesInFlight() nothrow { return(cast(uint)swapChainImages.length + 1); }
}

/** Shutdown ImGui and deAllocate all vulkan related objects in existance
 */
void cleanUp(App app) {
  SDL_Log("Wait on device idle & frame deletion queue");
  enforceVK(vkDeviceWaitIdle(app.device));
  app.frameDeletionQueue.flush(); // Frame deletion queue, flushes the buffers

  SDL_Log("Save ImGui Settings");
  saveSettings();

  SDL_Log("Shutdown ImGui");
  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);

  SDL_Log("Delete objects & flush the main deletion queue");
  foreach(object; app.objects) { app.cleanup(object); }
  app.mainDeletionQueue.flush();
  thread_joinAll();
  SDL_Log("Destroying window & quit SDL");
  SDL_DestroyWindow(app);
  SDL_Quit();
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

