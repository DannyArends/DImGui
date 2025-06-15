/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import std.algorithm : min;
import std.conv : to;
import io : isfile, readFile, writeFile;
import std.path : baseName;
import std.format : format;
import std.string : toStringz, fromStringz;

import geometry : Geometry, position, scale, rotate;
import lights : Light;
import devices : getMSAASamples;
import sfx : play;

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

  uint size = 1;
  float scaleF = 1.0f;
  float[3] rotF = [0.0f, 0.0f, 0.0f];

  float[2] rot = [-360.0, 360];
  float[2] pos = [-10.0, 10];
  float[2] col = [0.0, 2.0f];
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
  char[] data = (to!string(" ")).dup;
  writeFile("imgui.ini", data, true);
  SDL_Log("Cleared ImGui data");
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
  font_cfg.SizePixels = 36.0f;
  font_cfg.FontDataOwnedByAtlas = false;
  app.gui.fonts ~= ImFontAtlas_AddFontFromMemoryTTF(app.gui.io.Fonts, cast(void*)&data[0], size, 36, font_cfg, null);

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
    RenderPass : app.imguipass,
    MSAASamples : app.getMSAASamples(),
    CheckVkResultFn : &enforceVK
  };
  ImGui_ImplVulkan_Init(&imguiInit);
  version(Android){ 
    auto style = igGetStyle();
    ImGuiStyle_ScaleAllSizes(style, 2.0f);
    app.gui.size = 2;
  }
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

  VkRect2D renderArea = { extent: { width: app.camera.width, height: app.camera.height } };

  VkRenderPassBeginInfo renderPassInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass : app.imguipass,
    framebuffer : app.swapChainFramebuffers[app.frameIndex],
    renderArea : renderArea,
    clearValueCount : app.clearValue.length,
    pClearValues : &app.clearValue[0]
  };
  vkCmdBeginRenderPass(app.imguiBuffers[syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);

  // Render UI
  ImDrawData* drawData = app.renderGUI();
  ImGui_ImplVulkan_RenderDrawData(drawData, app.imguiBuffers[syncIndex], null);

  vkCmdEndRenderPass(app.imguiBuffers[syncIndex]);

  enforceVK(vkEndCommandBuffer(app.imguiBuffers[syncIndex]));
  if(app.trace) SDL_Log("Done recordImGuiCommandBuffer");
}

/** Show the GUI window with FPS statistics
 */
void showFPSwindow(ref App app, uint font = 1) {
  igPushFont(app.gui.fonts[font]);
  ImVec2 size;
  igCalcTextSize(&size, "Hello", null, false, 0.0f);

  igSetNextWindowPos(ImVec2(0.0f, size.y + 5.0f), 0, ImVec2(0.0f, 0.0f));
  auto flags = ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;
  igBegin("FPS", null, flags);
    igText("%s", app.properties.deviceName.ptr);
    igText("Vulkan v%d.%d.%d", VK_API_VERSION_MAJOR(app.properties.apiVersion),
                               VK_API_VERSION_MINOR(app.properties.apiVersion),
                               VK_API_VERSION_PATCH(app.properties.apiVersion));
    igText("%.1f FPS, %.1f ms", app.gui.io.Framerate, 1000.0f / app.gui.io.Framerate);
    igText("%d objects, %d textures", app.objects.length, app.textures.length);
    igText("C: [%.1f, %.1f, %.1f]", app.camera.position[0], app.camera.position[1], app.camera.position[2]);
    igText("F: [%.1f, %.1f, %.1f]", app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2]);
  igEnd();
  igPopFont();
}

/** Show the GUI window which allows us to manipulate 3D objects
 */
void showObjectswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBegin("Objects", show, 0)) {
    bool list = true;
    for(size_t x = 0; x < app.objects.length; x++) {
      if(app.objects[x].window){
        app.showObjectwindow(app.objects[x]);
        list = false;
      }
    }
    if(list){
      igBeginTable("Object_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

      foreach(i, object; app.objects){
        igPushID_Int(to!int(i));
        auto p = app.objects[i].position;
        igTableNextRow(0, 5.0f);
        string text = to!string(i);
        if(object.name) text = object.name() ~ " " ~ text;
        igTableNextColumn();
          igText(text.toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          if(igButton("Info", ImVec2(0.0f, 0.0f))){ app.objects[i].window = true; } igSameLine(0,5);
          if(igButton((app.objects[i].isVisible?"Hide":"Show"), ImVec2(0.0f, 0.0f))) { app.objects[i].isVisible = !app.objects[i].isVisible; } igSameLine(0,5);
          if(igButton("DeAllocate", ImVec2(0.0f, 0.0f))){ app.objects[i].deAllocate = true; } igSameLine(0,5);

        igPopID();
        }
      igEndTable();
      igEnd();
    }
  }else { igEnd(); }
  igPopFont();
}

/** Show the GUI window which shows loaded Textures
 */
void showTextureswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBegin("Textures", show, 0)){
    igBeginTable("Texture_Tbl", 3,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, texture; app.textures) {
      float ratio = cast(float)(texture.height) / texture.width;
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(toStringz(baseName(fromStringz(texture.path))), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igText("%d x %d", texture.width, texture.height);
      igTableNextColumn();
      igImage(cast(ImTextureID)texture.imID, ImVec2(100, min(100, cast(uint)(100 * ratio))), ImVec2(0, 0), ImVec2(1, 1));
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

/** Show the GUI window for Sound Effects
 */
void showSFXwindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBegin("Sounds", show, 0)){
    igSliderScalar("Volume", ImGuiDataType_Float,  &app.soundEffectGain, &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0); 
    igBeginTable("Sounds_Tbl", 2,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, sound; app.soundfx) {
      igPushID_Int(to!int(i));
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(toStringz(baseName(fromStringz(sound.path))), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      if(igButton("Play", ImVec2(0.0f, 0.0f))){ app.play(sound); }
      igPopID();
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

/** Individual Object
 */
void showObjectwindow(ref App app, ref Geometry obj) {
  igText(toStringz(format("Name: %s", obj.name())), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Vertices: %s", obj.vertices.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Indices: %s", obj.indices.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Instances: %s", obj.instances.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Topology: %s", obj.topology)), ImVec2(0.0f, 0.0f));
  auto p = obj.position;
  if(igButton("Overview", ImVec2(0.0f, 0.0f))) { obj.window = false; } igSameLine(0,5);
  if(igButton((obj.isVisible?"Hide":"Show"), ImVec2(0.0f, 0.0f))) { obj.isVisible = !obj.isVisible; } igSameLine(0,5);
  if(igButton("DeAllocate", ImVec2(0.0f, 0.0f))){ obj.deAllocate = true; }
  igBeginTable(toStringz(obj.name() ~ "_Tbl"), 4,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    igTableNextColumn();
      igText("Position", ImVec2(0.0f, 0.0f)); 
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##x", ImGuiDataType_Float,  &p[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##y", ImGuiDataType_Float,  &p[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##z", ImGuiDataType_Float,  &p[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();

    igTableNextColumn();
      if(igButton("Scale", ImVec2(0.0f, 0.0f))){ obj.scale([app.gui.scaleF, app.gui.scaleF, app.gui.scaleF]); app.gui.scaleF = 1.0f; }
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##zS", ImGuiDataType_Float, &app.gui.scaleF, &app.gui.scale[0], &app.gui.scale[1], "%.3f", 0); 
      igPopItemWidth();
    igTableNextColumn();
    igTableNextColumn();

    igTableNextColumn();
      if(igButton("Rotate", ImVec2(0.0f, 0.0f))){ obj.rotate(app.gui.rotF); app.gui.rotF = [0.0f,0.0f,0.0f]; }
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##xR", ImGuiDataType_Float,  &app.gui.rotF[0], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##yR", ImGuiDataType_Float,  &app.gui.rotF[1], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##zR", ImGuiDataType_Float,  &app.gui.rotF[2], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();

    obj.position = p;
  igEndTable();
  igEnd();
}

/** Show the GUI window with global settings
 */
void showSettingswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBegin("Settings", show, 0)){
    igBeginTable("Settings_Tbl", 2,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    igTableNextColumn();
    igText("Total Frames", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igText(toStringz(format("%s", app.totalFramesRendered)), ImVec2(0.0f, 0.0f));

    igTableNextColumn();
    igText("Deletion Queues", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igText(toStringz(format("%d / %d / %d", app.bufferDeletionQueue.length, app.frameDeletionQueue.length, app.mainDeletionQueue.length)), ImVec2(0.0f, 0.0f));

/*    igTableNextColumn();
    igText("Verbose", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igCheckbox("##Verbose", &app.verbose); */

    //igTableNextColumn();
    //if(igButton("Clear GUI Settings", ImVec2(0.0f, 0.0f))){ clearSettings(); loadSettings(); }

    igTableNextColumn();
    igText("Volume", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igSliderScalar("##", ImGuiDataType_Float,  &app.soundEffectGain, &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0); 

    igTableNextColumn();
    igText("showBounds", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igCheckbox("##showBounds", &app.showBounds);

    igTableNextColumn();
    igText("showRays", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igCheckbox("##showRays", &app.showRays);

    igTableNextColumn();
    igText("Clear color", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(75);
    igSliderScalar("##colR", ImGuiDataType_Float,  &app.clearValue[0].color.float32[0], &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);igSameLine(0,5);
    igPushItemWidth(75);
    igSliderScalar("##colG", ImGuiDataType_Float,  &app.clearValue[0].color.float32[1], &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);igSameLine(0,5);
    igPushItemWidth(75);
    igSliderScalar("##colB", ImGuiDataType_Float,  &app.clearValue[0].color.float32[2], &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);

    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

/** Show the GUI window for Shaders
 */
void showShaderwindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBegin("Shaders", show, 0)){
    igBeginTable("Shaders_Tbl", 3,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, shader; (app.shaders ~ app.compute.shaders)) {
      igPushID_Int(to!int(i));
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(toStringz(baseName(fromStringz(shader.path))), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igText(toStringz(format("%s", shader.stage)), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igText(toStringz(format("Descriptors: %s\nExecute as [%d, %d, %d]", shader.descriptors.length, shader.groupCount[0], shader.groupCount[1], shader.groupCount[2])), ImVec2(0.0f, 0.0f));
      igPopID();
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

/** Show the GUI window which allows us to manipulate lighting
 */
void showLightswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBegin("Lights", show, 0)){
    igBeginTable("Lights_Tbl", 2,  ImGuiTableFlags_Resizable, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, ref Light light; app.lights) {
      igPushID_Int(to!int(i));
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(format("light %d",i).toStringz, ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igBeginTable("Light_Tbl", 2,  ImGuiTableFlags_Resizable, ImVec2(0.0f, 0.0f), 0.0f);
        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Position".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##pX", ImGuiDataType_Float,  &light.position[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##pY", ImGuiDataType_Float,  &light.position[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##pZ", ImGuiDataType_Float,  &light.position[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);

        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Intensity".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##I0", ImGuiDataType_Float,  &light.intensity[0], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##I1", ImGuiDataType_Float,  &light.intensity[1], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##I2", ImGuiDataType_Float,  &light.intensity[2], &app.gui.col[0], &app.gui.col[1], "%.2f", 0);

        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Direction".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##D0", ImGuiDataType_Float,  &light.direction[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##D1", ImGuiDataType_Float,  &light.direction[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.size);
          igSliderScalar("##D2", ImGuiDataType_Float,  &light.direction[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
        igEndTable();
      igPopID();
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

/** Main Menu
 */
void showMenu(ref App app, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBeginMainMenuBar()) {
    if(igBeginMenu("File".toStringz, true)) {
      if(igMenuItem_Bool("FPS".toStringz,null, false, true)) {  app.gui.showFPS = !app.gui.showFPS; }
      if(igMenuItem_Bool("Demo".toStringz,null, false, true)) {  app.gui.showDemo = !app.gui.showDemo; }
      if(igMenuItem_Bool("Objects".toStringz,null, false, true)) { app.gui.showObjects = !app.gui.showObjects; }
      if(igMenuItem_Bool("Sounds".toStringz,null, false, true)) { app.gui.showSFX = !app.gui.showSFX; }
      if(igMenuItem_Bool("Shaders".toStringz,null, false, true)) { app.gui.showShaders = !app.gui.showShaders; }
      if(igMenuItem_Bool("Settings".toStringz,null, false, true)) { app.gui.showSettings = !app.gui.showSettings; }
      if(igMenuItem_Bool("Lights".toStringz,null, false, true)) { app.gui.showLights = !app.gui.showLights; }
      if(igMenuItem_Bool("Textures".toStringz,null, false, true)) {  app.gui.showTexture = !app.gui.showTexture; }
      igEndMenu();
    }
    igEndMainMenuBar();
  }
  igPopFont();
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

  igRender();
  return(igGetDrawData());
}

