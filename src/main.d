// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

import engine;
import validation;

import commands : createCommandPool;
import descriptor : createImGuiDescriptorPool;
import devices : createLogicalDevice;
import events : handleEvents;
import frame : presentFrame, renderFrame;
import glyphatlas : loadGlyphAtlas, createFontTexture;
import scene : createScene;
import imgui : initializeImGui;
import instance : createInstance;
import sdl : initializeSDL;
import shaders : createShadersStages;
import surface : createSurface;
import textures : loadTextures, createSampler;
import window: createOrResizeWindow, checkForResize;

void main(string[] args) {
  App app = initializeSDL();
  app.loadGlyphAtlas();
  app.createInstance();
  app.createDebugCallback();
  app.createLogicalDevice();
  app.createShadersStages();
  app.createCommandPool();
  app.createSampler();
  app.createFontTexture();
  app.loadTextures();
  app.createImGuiDescriptorPool();
  app.createSurface();
  app.createScene();
  app.createOrResizeWindow();   // Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui();        // Initialize ImGui (IO, Style, etc)

  uint frames = 500000;
  while (!app.finished && app.totalFramesRendered < frames) { // Main loop
    app.handleEvents();
    if(SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) { SDL_Delay(10); continue; }

    app.checkForResize();
    app.renderFrame();
    app.presentFrame();
    app.totalFramesRendered++;
  }
  app.cleanUp();
}

