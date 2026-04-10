/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : createCommandPools;
import compute : initializeCompute;
import descriptor : createImGuiDescriptorPool, createImGuiDescriptorSetLayout;
import devices : createLogicalDevice;
import events : handleEvents, sdlEventsFilter, removeGeometry;
import frame : presentFrame, renderFrame;
import glyphatlas : loadGlyphAtlas, uploadFont;
import io: ensureWorldDir;
import imgui : initializeImGui;
import instance : createInstance;
import scene : createScene;
import sdl : initializeSDL, SDL_WINDOW_MINIMIZED;
import shadow : createShadowMap;
import shaders : createCompiler, loadShaders, RenderShaders, PostProcessShaders;
import reflection : createReflectionContext;
import sampler : createSampler;
import surface : createSurface, getBestColorFormat;
import sfx : loadAllSoundEffect;
import textures : Texture;
import tileatlas : createTileAtlas;
import threading : initializeAsync, checkAsync;
import validation : createDebugCallback;
import vulkan : cleanup;
import window: createOrResizeWindow, checkForResize;

/* Main entry point to the program */
version (Android) {
  import core.runtime : rt_init;

  extern(C) int SDL_main(int argc, char** argv) { // Hijack the SDL main
    int dRuntime = rt_init();
    printf("D runtime initialized: %d", dRuntime);
    run(["android", format("--dRuntime=%s", dRuntime)]);
    return(0);
  }
// Other OS can just call run() directly (No known issues with garbage collection)
} else { 
  int main (string[] args) { run(args); return(0); }
}

/** 
 * Main entry point for Windows and Linux
 */
void run(string[] args = null) {
  App app = initializeSDL();                                    /// Initialize SDL library and create a window

  app.createCompiler();                                         /// Create the SPIR-V compiler
  app.createReflectionContext();                                /// Create a SPIR-V reflection context
  app.loadGlyphAtlas();                                         /// Load & parse the Glyph Atlas
  app.loadAllSoundEffect();                                     /// Load all available sound effects
  app.createInstance();                                         /// Create a Vulkan instance
  app.createDebugCallback();                                    /// Hook the debug callback to the validation layer
  app.createLogicalDevice();                                    /// Create a logical device for rendering
  app.getBestColorFormat();                                     /// Figure out the best available color format for HDR
  app.loadShaders(app.shaders, RenderShaders);                  /// Load the Rendering shaders
  app.loadShaders(app.postProcess, PostProcessShaders);         /// Load the Post-processing shaders
  if(app.hasCompute) app.initializeCompute();                   /// Load the compute shader
  app.createShadowMap();                                        /// Create the shadow resources, renderpass, and shader
  app.createCommandPools();                                     /// Create the rendering CommandPool
  app.createSampler();                                          /// Create a texture sampler
  app.createImGuiDescriptorPool();                              /// ImGui DescriptorPool
  app.createImGuiDescriptorSetLayout();                         /// ImGui DescriptorSet layout
  app.createTileAtlas();                                        /// before creating TileMap
  app.uploadFont();                                             /// Upload the Font Texture to GPU
  app.createSurface();                                          /// Create Vulkan rendering surface
  app.createOrResizeWindow();                                   /// Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui();                                        /// Initialize ImGui (IO, Style, etc)
  app.ensureWorldDir();                                         /// Ensure the world directory exists
  app.createScene();                                            /// Create our scene with geometries
  app.initializeAsync();                                        /// Start Async loading objects and textures

  app.time[LASTTICK] = app.time[STARTUP] = SDL_GetTicks();
  uint frames = 150000;
  while (!app.finished && app.totalFramesRendered < frames) {   /// Event polling & rendering Loop
    app.checkAsync();
    app.handleEvents();

    app.time[FRAMESTART] = SDL_GetTicks();
    if((SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) || app.isMinimized) { SDL_Delay(10); continue; }

    app.checkForResize();     // Check for resize
    app.renderFrame();        // Reder frame
    app.removeGeometry();     // Remove stale geometry
    app.presentFrame();       // Show frame
    app.totalFramesRendered++;
    app.time[FRAMESTOP] = SDL_GetTicks();
  }
  SDL_Log("Quit after %d / %d frames", app.totalFramesRendered, frames);
  app.cleanup();
}

