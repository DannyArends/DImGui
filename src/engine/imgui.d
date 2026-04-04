/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

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
import validation : nameVulkanObject, pushLabel, popLabel;

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

  float uiscale = 1;
  uint fontsize(){ 
    version(Android){ return(cast(uint)(20 * uiscale)); }else{ return(cast(uint)(16 * uiscale)); }
  }
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
    path = toStringz(format("%s/%s", fromStringz(SDL_GetAndroidInternalStoragePath()), fromStringz(path)));
  }
  if(path.isfile()) {
    SDL_Log("Loading ImGui settings from %s", path);
    auto content = readFile(path);
    auto s = (to!string(content));
    igLoadIniSettingsFromMemory(toStringz(s), content.length);
  }
}

/** FontAwesome icon as const(char)*
 */
const(char)* faIcon(string s = cast(string)ICON_FA_SEARCH){ return(toStringz(format("%s", s))); }

/** Code to initialize the ImGui backend
 */
void initializeImGui(ref App app){
  igCreateContext(null);
  app.gui.io = igGetIO_Nil();
  loadSettings();

  // Load the Roboto-Regular font
  char[] fm = readFile("data/fonts/Roboto-Regular.ttf");
  ImFontConfig* font_cfg = ImFontConfig_ImFontConfig();
  font_cfg.Name = "Roboto-Medium";
  font_cfg.FontDataOwnedByAtlas = false;
  app.gui.fonts ~= ImFontAtlas_AddFontFromMemoryTTF(app.gui.io.Fonts, cast(void*)&fm[0], cast(uint)fm.length, 18, font_cfg, null);

  // Load & Merge FontAwesome into the Roboto-Regular font
  ImFontConfig* merge_cfg = ImFontConfig_ImFontConfig();
  merge_cfg.Name = "FontAwesome";
  merge_cfg.MergeMode = true;
  merge_cfg.FontDataOwnedByAtlas = false;
  const(ImWchar)[] icon_ranges = [ICON_MIN_FA, ICON_MAX_FA, 0];
  char[] fa = readFile("data/fonts/FontAwesome.ttf");
  ImFontAtlas_AddFontFromMemoryTTF(app.gui.io.Fonts, cast(void*)&fa[0], cast(uint)fa.length, 18, merge_cfg, &icon_ranges[0]);

  app.gui.io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  //app.gui.io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;       // Enable Docking Controls
  version(Android) {
    app.gui.io.ConfigFlags |= ImGuiConfigFlags_IsTouchScreen ;      // Enable TouchScreen
  }
  igStyleColorsDark(null);
  SDL_Log("ImGuiIO: %p", app.gui.io);
  ImGui_ImplSDL3_InitForVulkan(app.window);

  ImGui_ImplVulkan_InitInfo imguiInit = {
    Instance : app.instance,
    PhysicalDevice : app.physicalDevice,
    Device : app.device,
    QueueFamily : app.queueFamily,
    Queue : app.queue,
    DescriptorPool : app.pools[Stage.IMGUI],
    Allocator : app.allocator,
    MinImageCount : app.imageCount,
    ImageCount : cast(uint)app.framesInFlight,
    RenderPass : app.imguiPass.pass,
    MSAASamples : VK_SAMPLE_COUNT_1_BIT,
    CheckVkResultFn : &enforceVK
  };

  ImGui_ImplVulkan_Init(&imguiInit);

  version(Android){ 
    app.gui.uiscale = 2.5;
    auto style = igGetStyle();
    ImGuiStyle_ScaleAllSizes(style, app.gui.uiscale);
    style.ScrollbarSize = 40.0f;
  }
  app.isImGuiInitialized = true;
  if(app.verbose) SDL_Log("ImGui initialized, MSAA: %d", app.getMSAASamples());
}

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 */
void recordImGuiCommandBuffer(ref App app, uint syncIndex) {
  if(app.trace) SDL_Log("recordImGuiCommandBuffer");
  auto cmd = app.imguiPass.commands[syncIndex];
  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  enforceVK(vkResetCommandBuffer(cmd, 0)); // Reset for recording
  enforceVK(vkBeginCommandBuffer(cmd, &commandBufferInfo));
  app.nameVulkanObject(cmd, toStringz(format("[COMMANDBUFFER] ImGui %d", syncIndex)), VK_OBJECT_TYPE_COMMAND_BUFFER);

  pushLabel(cmd, "ImGui", Colors.lightgray);

  // Render UI - must be called before begin() so rotation is applied before GPU submission
  ImDrawData* drawData = app.renderGUI();

  app.imguiPass.begin(cmd, app.frameIndex, app.camera.currentExtent, app.clearValue);
  ImGui_ImplVulkan_RenderDrawData(drawData, cmd, null);

  app.imguiPass.end(cmd);

  popLabel(cmd);

  enforceVK(vkEndCommandBuffer(cmd));
  if(app.trace) SDL_Log("Done recordImGuiCommandBuffer");
}

/** Rotate all ImGui vertices to handle Vulkan pre-rotation on Android.
 *  ImGui lays out in DisplaySize space. We remap into extentW x extentH framebuffer.
 */
version(Android) {
  ImVec2 remapPoint(float x, float y, float dW, float dH, float W, float H, VkSurfaceTransformFlagBitsKHR t) {
    if (t & VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR)  return ImVec2((1.0f - y/dH)*W, (x/dW)*H);
    if (t & VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR) return ImVec2((y/dH)*W, (1.0f - x/dW)*H);
    if (t & VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR) return ImVec2((1.0f - x/dW)*W, (1.0f - y/dH)*H);
    return ImVec2(x, y);
  }

  void rotateImGui(ImDrawData* drawData, VkSurfaceTransformFlagBitsKHR transform, uint extentW, uint extentH) {
    if (transform == VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR) return;
    float W = cast(float)extentW, H = cast(float)extentH;
    float dW = drawData.DisplaySize.x, dH = drawData.DisplaySize.y;
    for (int n = 0; n < drawData.CmdListsCount; n++) {
      ImDrawVert* verts = drawData.CmdLists.Data[n].VtxBuffer.Data;
      for (int i = 0; i < drawData.CmdLists.Data[n].VtxBuffer.Size; i++) {
        auto p = remapPoint(verts[i].pos.x, verts[i].pos.y, dW, dH, W, H, transform);
        verts[i].pos.x = p.x; verts[i].pos.y = p.y;
      }
      ImDrawCmd* cmds = drawData.CmdLists.Data[n].CmdBuffer.Data;
      for (int i = 0; i < drawData.CmdLists.Data[n].CmdBuffer.Size; i++) {
        auto mn = remapPoint(cmds[i].ClipRect.x, cmds[i].ClipRect.y, dW, dH, W, H, transform);
        auto mx = remapPoint(cmds[i].ClipRect.z, cmds[i].ClipRect.w, dW, dH, W, H, transform);
        cmds[i].ClipRect.x = mn.x < mx.x ? mn.x : mx.x;
        cmds[i].ClipRect.y = mn.y < mx.y ? mn.y : mx.y;
        cmds[i].ClipRect.z = mn.x > mx.x ? mn.x : mx.x;
        cmds[i].ClipRect.w = mn.y > mx.y ? mn.y : mx.y;
      }
    }
  }
}

/** Render the GUI and return the ImDrawData*
 */
ImDrawData* renderGUI(ref App app){
  // Start ImGui frame
  ImGui_ImplVulkan_NewFrame();
  ImGui_ImplSDL3_NewFrame();
  igNewFrame();
  uint font = 0;

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
  auto drawData = igGetDrawData();
  version(Android) { rotateImGui(drawData, app.camera.currentTransform, app.camera.currentExtent.width, app.camera.currentExtent.height); }
  return(drawData);
}

