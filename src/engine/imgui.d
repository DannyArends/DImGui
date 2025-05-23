/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import std.algorithm : min;
import std.conv : to;
import std.path : baseName;
import std.format : format;
import std.string : toStringz, fromStringz;

import geometry : position;
import lights : Light;
import devices : getSampleCount;
import sfx : play;

/** Main GUI structure
 */
struct GUI {
  bool showDemo = false;
  bool showFPS = true;
  bool showObjects = false;
  bool showLights = false;
  bool showSFX = false;
  bool showTexture = false;
  float[2] pos = [-50.0, 50];
  float[2] col = [0.0, 2.0f];
  float[2] sound = [0.0, 1.0f];
}

/** Code to initialize the ImGui backend
 */
void initializeImGui(ref App app){
  igCreateContext(null);
  app.io = igGetIO_Nil();
  app.fonts ~= ImFontAtlas_AddFontDefault(app.io.Fonts, null);
  app.fonts ~= ImFontAtlas_AddFontFromFileTTF(app.io.Fonts, "assets/fonts/FreeMono.ttf", 12, null, null);
  app.io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  app.io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;         // Enable Docking Controls
  igStyleColorsDark(null);
  if(app.verbose) SDL_Log("ImGuiIO: %p", app.io);
  ImGui_ImplSDL2_InitForVulkan(app.window);

  ImGui_ImplVulkan_InitInfo imguiInit = {
    Instance : app.instance,
    PhysicalDevice : app.physicalDevice,
    Device : app.device,
    QueueFamily : app.queueFamily,
    Queue : app.queue,
    DescriptorPool : app.imguiPool,
    Allocator : app.allocator,
    MinImageCount : app.camera.minImageCount,
    ImageCount : cast(uint)app.framesInFlight,
    RenderPass : app.imguiPass,
    MSAASamples : app.getSampleCount(),
    CheckVkResultFn : &enforceVK
  };
  ImGui_ImplVulkan_Init(&imguiInit);
  if(app.verbose) SDL_Log("ImGui initialized");
}

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 */
void recordImGuiCommandBuffer(ref App app, uint syncIndex) {
  if(app.verbose) SDL_Log("recordImGuiCommandBuffer");
  enforceVK(vkResetCommandBuffer(app.imguiBuffers[syncIndex], 0));

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  enforceVK(vkBeginCommandBuffer(app.imguiBuffers[syncIndex], &commandBufferInfo));

  VkRect2D renderArea = { extent: { width: app.camera.width, height: app.camera.height } };

  VkRenderPassBeginInfo renderPassInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass : app.imguiPass,
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
  if(app.verbose) SDL_Log("Done recordImGuiCommandBuffer");
}

/** Show the GUI window with FPS statistics
 */
void showFPSwindow(ref App app, uint font = 1) {
  igPushFont(app.fonts[font]);
  igSetNextWindowPos(ImVec2(0.0f, 20.0f), 0, ImVec2(0.0f, 0.0f));
  auto flags = ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;
  igBegin("FPS", null, flags);
    igText("%s", app.properties.deviceName.ptr);
    igText("Vulkan v%d.%d.%d", VK_API_VERSION_MAJOR(app.properties.apiVersion),
                     VK_API_VERSION_MINOR(app.properties.apiVersion),
                     VK_API_VERSION_PATCH(app.properties.apiVersion));
    igText("%.1f FPS, %.1f ms %d objects, %d textures", app.io.Framerate, 1000.0f / app.io.Framerate, app.objects.length, app.textures.length);
    igText("C: [%.1f, %.1f, %.1f]", app.camera.position[0], app.camera.position[1], app.camera.position[2]);
    igText("F: [%.1f, %.1f, %.1f]", app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2]);
  igEnd();
  igPopFont();
}

/** Show the GUI window which allows us to manipulate 3D objects
 */
void showObjectswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.fonts[font]);
  if(igBegin("Objects", show, ImGuiWindowFlags_NoFocusOnAppearing)){
    igBeginTable("Object_Tbl", 5,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

    foreach(i, object; app.objects){
      igPushID_Int(to!int(i));
      auto p = app.objects[i].position;
      igTableNextRow(0, 5.0f);
      string text = to!string(i);
      if(object.name) text = object.name() ~ " " ~ text;
      igTableNextColumn();
      igText(text.toStringz, ImVec2(0.0f, 0.0f));
      igTableNextColumn();
        if(igButton((app.objects[i].isVisible?"H":"S"), ImVec2(0.0f, 0.0f))) { app.objects[i].isVisible = !app.objects[i].isVisible; } igSameLine(0,5);
        if(igButton("X", ImVec2(0.0f, 0.0f))){ app.objects[i].deAllocate = true; }
      igTableNextColumn();
        igPushItemWidth(100);
          igSliderScalar("##x", ImGuiDataType_Float,  &p[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
        igPopItemWidth();
      igTableNextColumn();
        igPushItemWidth(100);
          igSliderScalar("##y", ImGuiDataType_Float,  &p[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
        igPopItemWidth();
      igTableNextColumn();
        igPushItemWidth(100);
          igSliderScalar("##z", ImGuiDataType_Float,  &p[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
        igPopItemWidth();
      app.objects[i].position = p;
      igPopID();
      }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

/** Show the GUI window which shows loaded Textures
 */
void showTextureswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.fonts[font]);
  if(igBegin("Textures", show, ImGuiWindowFlags_NoFocusOnAppearing)){
    igBeginTable("Texture_Tbl", 3,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, texture; app.textures) {
      float ratio = cast(float)(texture.height) / texture.width;
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(toStringz(baseName(fromStringz(texture.path))), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igText("%d x %d", texture.width, texture.height);
      igTableNextColumn();
      igImage(cast(ImTextureID)texture.descrSet, ImVec2(100, min(100, cast(uint)(100 * ratio))), ImVec2(0, 0), ImVec2(1, 1));
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

/** Show the GUI window for Sound Effects
 */
void showSFXwindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.fonts[font]);
  if(igBegin("Sounds", show, ImGuiWindowFlags_NoFocusOnAppearing)){
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

/** Show the GUI window which allows us to manipulate lighting
 */
void showLightswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.fonts[font]);
  if(igBegin("Lights", show, ImGuiWindowFlags_NoFocusOnAppearing)){
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
          igPushItemWidth(75);
          igSliderScalar("##pX", ImGuiDataType_Float,  &light.position[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75);
          igSliderScalar("##pY", ImGuiDataType_Float,  &light.position[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75);
          igSliderScalar("##pZ", ImGuiDataType_Float,  &light.position[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);

        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Intensity".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75);
          igSliderScalar("##I0", ImGuiDataType_Float,  &light.intensity[0], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75);
          igSliderScalar("##I1", ImGuiDataType_Float,  &light.intensity[1], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75);
          igSliderScalar("##I2", ImGuiDataType_Float,  &light.intensity[2], &app.gui.col[0], &app.gui.col[1], "%.2f", 0);

        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Direction".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75);
          igSliderScalar("##D0", ImGuiDataType_Float,  &light.direction[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75);
          igSliderScalar("##D1", ImGuiDataType_Float,  &light.direction[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75);
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
  if(igBeginMainMenuBar()) {
    if(igBeginMenu("File".toStringz, true)) {
      if(igMenuItem_Bool("FPS".toStringz,null, false, true)) {  app.gui.showFPS = !app.gui.showFPS; }
      if(igMenuItem_Bool("Demo".toStringz,null, false, true)) {  app.gui.showDemo = !app.gui.showDemo; }
      if(igMenuItem_Bool("Objects".toStringz,null, false, true)) { app.gui.showObjects = !app.gui.showObjects; }
      if(igMenuItem_Bool("Sounds".toStringz,null, false, true)) { app.gui.showSFX = !app.gui.showSFX; }
      if(igMenuItem_Bool("Lights".toStringz,null, false, true)) { app.gui.showLights = !app.gui.showLights; }
      if(igMenuItem_Bool("Textures".toStringz,null, false, true)) {  app.gui.showTexture = !app.gui.showTexture; }
      igEndMenu();
    }
    igEndMainMenuBar();
  }
}

/** Render the GUI and return the ImDrawData*
 */
ImDrawData* renderGUI(ref App app){
  // Start ImGui frame
  ImGui_ImplVulkan_NewFrame();
  ImGui_ImplSDL2_NewFrame();
  igNewFrame();
  app.showMenu();
  if(app.gui.showDemo) igShowDemoWindow(&app.gui.showDemo);
  if(app.gui.showFPS) app.showFPSwindow();
  if(app.gui.showObjects) app.showObjectswindow(&app.gui.showObjects);
  if(app.gui.showSFX) app.showSFXwindow(&app.gui.showSFX);
  if(app.gui.showLights) app.showLightswindow(&app.gui.showLights);
  if(app.gui.showTexture) app.showTextureswindow(&app.gui.showTexture);

  igRender();
  return(igGetDrawData());
}

