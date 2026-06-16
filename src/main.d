/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : createCommandPools;
import compute : initializeCompute;
import descriptor : createImGuiDescriptorPool, createImGuiDescriptorSetLayout, registerRenderProviders;
import devices : createLogicalDevice;
import events : sdlEventsFilter, removeGeometry;
import frame : waitForFrame, presentFrame, renderFrame;
import game : cleanupGame, checkGameAsync, GameApp, initGame, updateGame;
import glyphatlas : loadGlyphAtlas, uploadFont;
import imgui : initializeImGui;
import input : handleEvents;
import instance : createInstance;
import sdl : initializeSDL;
import shadow : createShadowMap;
import shaders : createCompiler, loadShaders, RenderShaders, PostProcessShaders;
import reflection : createReflectionContext;
import sampler : createSampler;
import surface : createSurface, getBestColorFormat;
import sfx : loadAllSoundEffect;
import textures : Texture;
import threading : initializeAsync, checkAsync;
import timing : timed;
import validation : createDebugCallback;
import vulkan : cleanup;
import window: createOrResizeWindow, checkForResize;

/** Main entry point to the program */
version (Android) {
  import core.runtime : rt_init;

  extern(C) int SDL_main(int argc, char** argv) { // Hijack the SDL main
    int dRuntime = rt_init();
    printf("D runtime initialized: %d", dRuntime);
    run(["android", format("--dRuntime=%s", dRuntime)]);
    return(0);
  }
// Other OS can just call run() directly (No known issues with garbage collection)
} else { int main (string[] args) { run(args); return(0); } }

/** Main entry point for Windows and Linux */
void run(string[] args = null) {
  GameApp app = GameApp(initializeSDL());                       /// Initialize SDL library and create a window
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
  app.registerRenderProviders();
  if(app.hasCompute) app.initializeCompute();                   /// Load the compute shader
  app.createShadowMap();                                        /// Create the shadow resources, renderpass, and shader
  app.createCommandPools();                                     /// Create the rendering CommandPool
  app.createSampler();                                          /// Create a texture sampler
  app.createImGuiDescriptorPool();                              /// ImGui DescriptorPool
  app.createImGuiDescriptorSetLayout();                         /// ImGui DescriptorSet layout
  app.uploadFont();                                             /// Upload the Font Texture to GPU
  app.createSurface();                                          /// Create Vulkan rendering surface
  app.createOrResizeWindow();                                   /// Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui();                                        /// Initialize ImGui (IO, Style, etc)
  app.initGame();                                               /// Load the chunk world
  app.initializeAsync();                                        /// Start Async loading objects and textures

  app.time[LASTTICK] = app.time[STARTUP] = SDL_GetTicks();
  uint frames = 150000;
  while (!app.finished && app.totalFramesRendered < frames) {   /// Event polling & render loop
    auto dt = app.timed!handleEvents();                           /// Handle SDL / user events
    app.timed!checkForResize();                                   /// Check for resize
    if(app.isMinimized) { SDL_Delay(10); continue; }              /// Minimized ? sleep and continue
    app.timed!removeGeometry();                                   /// Remove stale geometry
    app.timed!checkAsync();                                       /// Check ASync handlers
    app.timed!checkGameAsync();                                   /// Game specific ASync handlers

    app.timed!updateGame(dt);                                     /// Handle Game Updates
    app.waitForFrame();                                           /// Wait for a new frame (outside timing)
    app.time[FRAMESTART] = SDL_GetTicks();                        /// Start the clock
    app.timed!renderFrame(dt);                                    /// Render frame
    app.timed!presentFrame();                                     /// Show frame
    app.time[LASTFRAME] = app.time[FRAMESTOP];                    /// Remember last time we stopped ?
    app.time[FRAMESTOP] = SDL_GetTicks();                         /// Stop the clock
  }
  SDL_Log("Quit after %d / %d frames", app.totalFramesRendered, frames);
  app.cleanup();
}

