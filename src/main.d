/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import validation;

import commands : createCommandPool;
import compute : createComputeDescriptorPool, createComputeDescriptorSetLayout, createComputePipeline, createComputeDescriptorSet;
import descriptor : createImGuiDescriptorPool, createImGuiDescriptorSetLayout, addImGuiTexture;
import devices : createLogicalDevice;
import events : handleEvents;
import frame : presentFrame, renderFrame;
import glyphatlas : loadGlyphAtlas, createFontTexture;
import scene : createScene;
import imgui : initializeImGui;
import instance : createInstance;
import sdl : initializeSDL, START, STARTUP, FRAMESTART, LASTTICK;
import shaders : createShadersStages;
import surface : createSurface;
import sfx : loadAllSoundEffect;
import textures : Texture, loadTextures, createSampler;
import window: createOrResizeWindow, checkForResize;

/** 
 * Main entry point for Windows and Linux
 */
void main(string[] args) {
  App app = initializeSDL();
  app.loadGlyphAtlas();
  app.loadAllSoundEffect();
  app.createInstance();
  app.createDebugCallback();
  app.createLogicalDevice();
  app.createShadersStages();
  app.createCommandPool();

  app.createComputeDescriptorPool();
  app.createComputeDescriptorSetLayout();
  app.createComputePipeline();

  app.createSampler();
  app.createImGuiDescriptorPool();
  app.createImGuiDescriptorSetLayout();
  app.createFontTexture();
  app.loadTextures();

  app.createSurface();              /// Create rendering surface
  app.createScene();                /// Create a scene with Geometries
  app.createOrResizeWindow();       /// Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui();            /// Initialize ImGui (IO, Style, etc)
  app.time[LASTTICK] = app.time[STARTUP] = SDL_GetTicks();
  uint frames = 50000;
  while (!app.finished && app.totalFramesRendered < frames) { // Main loop
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

