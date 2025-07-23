/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : Colors;
import devices : getMSAASamples;
import io : isfile, readFile, writeFile;

import settingswindow : showSettingswindow;
import sfxwindow : showSFXwindow;
import directorywindow : showDirectoryWindow;
import fpswindow : showFPSwindow;
import objectswindow : showObjectswindow, showObjectwindow;
import lightswindow : showLightswindow;
import mainmenu : showMenu;
import shaderswindow : showShaderwindow;
import texturewindow : showTextureswindow;
import validation : pushLabel, popLabel;

/** Main GUI structure
 */
struct GUI {
  ImGuiIO* io;
  ImFont*[] fonts;

  bool showDemo = false;
  bool showFPS = true;
  bool showObjects = false;
  bool showLights = false;
  bool showSettings = false;
  bool showSFX = false;
  bool showShaders = false;
  bool showTexture = false;
  bool showDirectory = false;

  uint size = 1;
  float scaleF = 1.0f;
  float[3] rotF = [0.0f, 0.0f, 0.0f];

  float[2] rot = [-360.0, 360.0f];
  float[2] pos = [-10.0, 10];
  float[2] col = [0.0, 2.0f];
  float[2] cone = [0.0, 90.0f];
  float[2] scale = [0.001, 4.0f];
  float[2] sound = [0.0, 1.0f];
}

/** Save ImGui settings to disk (or Android internal storage)
 */
void saveSettings() {
  size_t ini_data_size = 0;
  const(char)* ini_data = igSaveIniSettingsToMemory(&ini_data_size);
  if (ini_data) {
    char[] data = (to!string(ini_data)).dup;
    writeFile("imgui.ini", data, true);
    SDL_Log("Saved ImGui INI data (size: %zu bytes)", ini_data_size);
  }
}

void clearSettings() {
  auto g = *igGetCurrentContext();
  for (int i = 0; i < g.Windows.Size; i++) {
    ImGuiWindow* window = g.Windows.Data[i];
    igClearWindowSettings(window.Name);
  }
}

/** Load ImGui settings from disk (or Android internal storage)
 */
void loadSettings(const(char)* path = "imgui.ini") {
  version (Android) {
    path = toStringz(format("%s/%s", fromStringz(SDL_AndroidGetInternalStoragePath()), fromStringz(path)));
  }
  if(path.isfile()) {
    SDL_Log("Loading ImGui settings from %s", path);
    auto content = readFile(path);
    auto s = (to!string(content));
    igLoadIniSettingsFromMemory(toStringz(s), content.length);
  }
}

/** Code to initialize the ImGui backend
 */
void initializeImGui(ref App app){
  igCreateContext(null);
  app.gui.io = igGetIO_Nil();
  loadSettings();
  // Load the Default font
  app.gui.fonts ~= ImFontAtlas_AddFontDefault(app.gui.io.Fonts, null);

  // Load our FreeMono.ttf font
  char[] data = readFile("data/fonts/FreeMono.ttf");
  uint size = cast(uint)data.length;
  ImFontConfig* font_cfg = ImFontConfig_ImFontConfig();
  font_cfg.Name = "FreeMono";
  font_cfg.SizePixels = 42.0f;
  font_cfg.FontDataOwnedByAtlas = false;
  app.gui.fonts ~= ImFontAtlas_AddFontFromMemoryTTF(app.gui.io.Fonts, cast(void*)&data[0], size, 42, font_cfg, null);

  app.gui.io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  //app.gui.io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;         // Enable Docking Controls
  version(Android) {
    app.gui.io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen ;         // Enable Docking Controls
  }
  igStyleColorsDark(null);
  if(app.verbose) SDL_Log("ImGuiIO: %p", app.gui.io);
  ImGui_ImplSDL2_InitForVulkan(app.window);

  ImGui_ImplVulkan_InitInfo imguiInit = {
    Instance : app.instance,
    PhysicalDevice : app.physicalDevice,
    Device : app.device,
    QueueFamily : app.queueFamily,
    Queue : app.queue,
    DescriptorPool : app.pools[IMGUI],
    Allocator : app.allocator,
    MinImageCount : app.imageCount,
    ImageCount : cast(uint)app.framesInFlight,
    RenderPass : app.imgui,
    MSAASamples : VK_SAMPLE_COUNT_1_BIT,
    CheckVkResultFn : &enforceVK
  };
  ImGui_ImplVulkan_Init(&imguiInit);
  ImGui_ImplVulkan_CreateFontsTexture();
  vkDeviceWaitIdle(app.device);
  version(Android){ 
    auto style = igGetStyle();
    ImGuiStyle_ScaleAllSizes(style, 2.0f);
    app.gui.size = 2;
  }
  app.isImGuiInitialized = true;
  if(app.verbose) SDL_Log("ImGui initialized, MSAA: %d", app.getMSAASamples());
}

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 */
void recordImGuiCommandBuffer(ref App app, uint syncIndex) {
  if(app.trace) SDL_Log("recordImGuiCommandBuffer");
  enforceVK(vkResetCommandBuffer(app.imguiBuffers[syncIndex], 0));

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  enforceVK(vkBeginCommandBuffer(app.imguiBuffers[syncIndex], &commandBufferInfo));

  pushLabel(app.imguiBuffers[app.syncIndex], "ImGui", Colors.lightgray);

  VkRect2D renderArea = { extent: { width: app.camera.width, height: app.camera.height } };

  VkRenderPassBeginInfo renderPassInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass : app.imgui,
    framebuffer : app.framebuffers.imgui[app.frameIndex],
    renderArea : renderArea,
    clearValueCount : app.clearValue.length,
    pClearValues : &app.clearValue[0]
  };
  vkCmdBeginRenderPass(app.imguiBuffers[syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);

  // Render UI
  ImDrawData* drawData = app.renderGUI();
  ImGui_ImplVulkan_RenderDrawData(drawData, app.imguiBuffers[syncIndex], null);

  vkCmdEndRenderPass(app.imguiBuffers[syncIndex]);

  popLabel(app.imguiBuffers[app.syncIndex]);

  enforceVK(vkEndCommandBuffer(app.imguiBuffers[syncIndex]));
  if(app.trace) SDL_Log("Done recordImGuiCommandBuffer");
}

/** Render the GUI and return the ImDrawData*
 */
ImDrawData* renderGUI(ref App app){
  // Start ImGui frame
  ImGui_ImplVulkan_NewFrame();
  ImGui_ImplSDL2_NewFrame();
  igNewFrame();
  uint font = 0;
  version (Android) { font = 1; }

  app.showMenu(font);
  if(app.gui.showDemo) igShowDemoWindow(&app.gui.showDemo);
  if(app.gui.showFPS) app.showFPSwindow(font);
  if(app.gui.showObjects) app.showObjectswindow(&app.gui.showObjects, font);
  if(app.gui.showSFX) app.showSFXwindow(&app.gui.showSFX, font);
  if(app.gui.showShaders) app.showShaderwindow(&app.gui.showShaders, font);
  if(app.gui.showSettings) app.showSettingswindow(&app.gui.showSettings, font);
  if(app.gui.showLights) app.showLightswindow(&app.gui.showLights, font);
  if(app.gui.showTexture) app.showTextureswindow(&app.gui.showTexture, font);
  if(app.gui.showDirectory) app.showDirectoryWindow(&app.gui.showDirectory, "data", font);

  igRender();
  return(igGetDrawData());
}

