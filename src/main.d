import engine;
import validation;

import commands : createCommandPool;
import descriptor : createImGuiDescriptorPool;
import devices : pickPhysicalDevice, createLogicalDevice;
import events : handleEvents;
import frame : presentFrame, renderFrame;
import glyphatlas : loadGlyphAtlas, createFontTexture;
import scene : createScene;
import imgui : initializeImGui;
import instance : createInstance;
import sdl : initializeSDL;
import surface : createSurface, querySurfaceCapabilities;
import textures : loadTextures, createSampler;
import window: createOrResizeWindow, checkForResize, renderGUI;

void main(string[] args) {
  App app = initializeSDL();
  app.loadGlyphAtlas();
  app.createInstance();
  app.createDebugCallback();
  app.createLogicalDevice();
  app.createCommandPool();
  app.createSampler();
  app.createFontTexture(app.glyphAtlas);
  app.loadTextures();
  app.createImGuiDescriptorPool();
  app.createSurface();
  app.createScene();

  app.createOrResizeWindow(); // Create window (swapchain, renderpass, framebuffers, etc)
  app.initializeImGui(); // Initialize ImGui (IO, Style, etc)

  uint frames = 4000;
  while (!app.finished && app.totalFramesRendered < frames) { // Main loop
    app.handleEvents();
    if(SDL_GetWindowFlags(app) & SDL_WINDOW_MINIMIZED) { SDL_Delay(10); continue; }

    app.checkForResize();
    ImDrawData* drawData = app.renderGUI();

    app.renderFrame(drawData);
    app.presentFrame();
    app.totalFramesRendered++;
  }
  app.cleanUp();
}

