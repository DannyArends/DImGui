/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import includes;

public import core.memory : GC;
public import core.stdc.string : strcmp, memcpy, strstr;
public import core.time : MonoTime;

public import std.algorithm : filter, map, min, remove, reverse, sort, swap;
public import std.array : array, split;
public import std.conv : to;
public import std.format : format;
public import std.file : exists, isFile, dirEntries, SpanMode;
public import std.math : abs, ceil, sqrt, PI, cos, sin, tan, acos, asin, atan, atan2;
public import std.path : baseName, extension, globMatch, stripExtension;
public import std.random : Random, uniform;
public import std.regex : regex, matchAll;
public import std.string : toStringz, fromStringz, lastIndexOf, startsWith, strip, chomp, splitLines;
public import std.traits : EnumMembers;
public import std.utf : isValidDchar;

import animation : Animation;
import bone : Bone;
import depthbuffer : DepthBuffer;
import camera : Camera;
import compute : Compute;
import deletion : CheckedDeletionQueue, DeletionQueue;
import glyphatlas : GlyphAtlas;
import geometry : Geometry, cleanup;
import lights : Light, Lights;
import matrix : multiply, inverse;
import node : Node;
import pipeline : GraphicsPipeline;
import images : ColorBuffer;
import imgui : GUI, saveSettings;
import shaders : Shader;
import vector : normalize;
import uniforms : UBO;
import sync : Sync, Fence;
import ssbo : SSBO;
import sfx : WavFMT;
import textures : Texture;

const(char)* IMGUI = "IMGUI"; 
const(char)* COMPUTE = "COMPUTE";
const(char)* RENDER = "RENDER";

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
  Compute compute;                                                              /// Compute shaders
  Geometry[] objects;                                                           /// All geometric objects for rendering
  Bone[string] bones;
  Texture[] textures;                                                           /// Textures
  WavFMT[] soundfx;                                                             /// Sound effects
  SSBO[const(char)*] buffers;                                                   /// SSBO buffers
  UBO[const(char)*] ubos;                                                       /// UBO buffers
  Light[4] lights = [Lights.White, Lights.Red, Lights.Green, Lights.Blue];      /// Scene lighting
  GUI gui;                                                                      /// ImGui related variables
  Camera camera;                                                                /// Our camera class
  GlyphAtlas glyphAtlas;                                                        /// GlyphAtlas for geometric font rendering

  VkSampler sampler;
  Shader[] shaders;
  GraphicsPipeline[VkPrimitiveTopology] pipelines;
  DepthBuffer depthBuffer;
  ColorBuffer colorBuffer;

  // Deletion queues for cleaning up resources
  DeletionQueue mainDeletionQueue;                                              /// On application shutdown
  DeletionQueue frameDeletionQueue;                                             /// When rebuilding the SwapChain
  CheckedDeletionQueue bufferDeletionQueue;                                     /// On each frame rendered

  // ShaderC & SPIR-V reflection
  shaderc_compiler_t compiler;                                                  /// ShaderC compiler
  shaderc_compile_options_t options;                                            /// ShaderC compiler options
  spvc_context context;                                                         /// SpirV context

  // Vulkan Instance related variables
  VkInstance instance = null;
  VkPhysicalDevice physicalDevice = null;
  VkPhysicalDeviceProperties properties;
  VkDevice device = null;
  VkQueue queue = null;

  VkDescriptorPool[const(char)*] pools;         /// Descriptor pools (IMGUI, COMPUTE, RENDER)
  VkDescriptorSetLayout[const(char)*] layouts;  /// Descriptor layouts (IMGUI, RENDER, N x computeShader.PATH)
  VkDescriptorSet[][const(char)*] sets;         /// Descriptor sets per Frames In FLight for (IMGUI, RENDER, N x computeShader.PATH)

  // Surface, Formats, SwapChain, and commandpool resources
  VkSurfaceKHR surface = null;
  VkSurfaceFormatKHR[] surfaceformats = null;   /// Available formats
  uint format = 0;                              /// selected format
  VkSwapchainKHR swapChain = null;
  VkCommandPool commandPool = null;

  // Per frame resources (reset when rebuilding the swapchain)
  Sync[] sync = null;
  Fence[] fences = null;
  VkImage[] swapChainImages = null;
  VkImageView[] swapChainImageViews = null;
  VkFramebuffer[] swapChainFramebuffers = null;

  VkRenderPass imguipass = null;
  VkRenderPass renderpass = null;

  VkCommandBuffer[] imguiBuffers = null;
  VkCommandBuffer[] renderBuffers = null;

  VkAllocationCallbacks* allocator = null;
  VkDebugReportCallbackEXT debugCallback = null;

  // Sync and Frame Tracking
  uint queueFamily = uint.max;                    /// Current queueFamily used
  uint syncIndex = 0;                             /// Sync index (Semaphore)
  uint frameIndex = 0;                            /// Current frame index (Fence)
  float soundEffectGain = 0.8;                    /// Sound Effects Gain
  ulong[5] time = [0, 0, 0, 0, 0];                /// Time monitoring (START, STARTUP, FRAMESTART, FRAMESTOP, LASTTICK)
  uint totalFramesRendered = 0;                   /// Total frames rendered so far

  const(char)*[] instanceExtensions;              /// Enabled instance extensions
  const(char)*[] deviceExtensions;                /// Enabled device extensions
  const(char)*[] layers;                          /// Enabled layers

  // Global boolean flags
  bool finished = false;                          /// Is the main loop finished ?
  bool showBounds = false;                        /// Show bounding boxes
  bool showRays = false;                          /// Show rays
  uint verbose = 0;                               /// Be very verbose
  bool rebuild = false;                           /// Rebuild the swapChain?
  bool isMinimized = false;                       /// isMinimized?

  // Properties based on the SwapChain
  @property uint imageCount() { return(cast(uint)swapChainImages.length); }
  @property bool trace() { return(verbose > 1); }
  @property uint framesInFlight() { return(cast(uint)swapChainImages.length + 1); }
}

/** Shutdown ImGui and deAllocate all vulkan related objects in existance
 */
void cleanUp(App app){
  if(app.verbose) SDL_Log("Save ImGui Settings");
  saveSettings();

  if(app.verbose) SDL_Log("Wait idle & frame deletion queue");
  enforceVK(vkDeviceWaitIdle(app.device));
  app.frameDeletionQueue.flush(); // Frame deletion queue, flushes the buffers

  if(app.verbose) SDL_Log("Shutdown ImGui");
  ImGui_ImplVulkan_Shutdown();
  ImGui_ImplSDL2_Shutdown();
  igDestroyContext(null);

  if(app.verbose) SDL_Log("Delete objects & main queue");
  // Delete objects and flush the main deletion queue
  foreach(object; app.objects) { app.cleanup(object); }
  app.mainDeletionQueue.flush();

  // Clear the ShaderC compiler and Quit SDL
  if(app.verbose) SDL_Log("Destroy window");
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
  writefln("[INFO] %s", fromStringz(message));
}

