/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import validation;

import commands : createCommandPool;
import compute : createComputeShaders;
import descriptor : createImGuiDescriptorPool, createImGuiDescriptorSetLayout;
import devices : createLogicalDevice;
import events : handleEvents;
import frame : presentFrame, renderFrame;
import glyphatlas : loadGlyphAtlas, createFontTexture;
import scene : createScene;
import imgui : initializeImGui;
import instance : createInstance;
import sdl : initializeSDL, START, STARTUP, FRAMESTART, LASTTICK;
import shaders : createCompiler, createRenderShaders;
import reflection : createReflectionContext;
import surface : createSurface;
import sfx : loadAllSoundEffect;
import textures : Texture, loadTextures, createSampler;
import window: createOrResizeWindow, checkForResize;

/** 
 * Main entry point for Windows and Linux
 */
void main(string[] args) {
  App app = initializeSDL();              /// Initialize SDL library and create a window
  app.createCompiler();                   /// Create the SPIR-V compiler
  app.createReflectionContext();          /// Create a SPIR-V reflection context
  app.loadGlyphAtlas();                   /// Load & parse the Glyph Atlas
  app.loadAllSoundEffect();               /// Load all available sound effects
  app.createInstance();                   /// Create a Vulkan instance
  app.createDebugCallback();              /// Hook the debug callback to the validation layer
  app.createLogicalDevice();              /// Create a logical device for rendering
  app.createRenderShaders();              /// Load the vertex and fragment shaders
  app.createComputeShaders();              /// Load the compute shader
  app.createCommandPool();                /// Create the rendering CommandPool
  app.createSampler();                    /// Create a texture sampler
  app.createImGuiDescriptorPool();        /// ImGui DescriptorPool
  app.createImGuiDescriptorSetLayout();   /// ImGui DescriptorSet layout
  app.createFontTexture();                /// Create a Texture from the GlyphAtlas
  app.loadTextures();                     /// Transfer all textures to the GPU
  app.createSurface();                    /// Create Vulkan rendering surface
  app.createOrResizeWindow();             /// Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui();                  /// Initialize ImGui (IO, Style, etc)
  app.createScene();                      /// Create our scene with geometries

  app.time[LASTTICK] = app.time[STARTUP] = SDL_GetTicks();
  uint frames = 500000;
  while (!app.finished && app.totalFramesRendered < frames) { /// Event polling & rendering Loop
    app.time[FRAMESTART] = SDL_GetTicks();
    app.handleEvents();
    if(SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) { SDL_Delay(10); continue; }

    app.checkForResize();
    app.renderFrame();
    app.presentFrame();
    app.totalFramesRendered++;
  }
  SDL_Log("Quit after %d / %d frames", app.totalFramesRendered, frames);
  app.cleanUp();
}
