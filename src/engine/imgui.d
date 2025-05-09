/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.conv : to;
import std.format : format;
import std.string : toStringz;

import geometry : position;
import devices : getSampleCount;

void initializeImGui(ref App app){
  igCreateContext(null);
  app.io = igGetIO_Nil();
  app.fonts ~= ImFontAtlas_AddFontDefault(app.io.Fonts, null);
  app.fonts ~= ImFontAtlas_AddFontFromFileTTF(app.io.Fonts, "assets/fonts/FreeMono.ttf", 12, null, null);
  app.io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
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
    ImageCount : cast(uint)app.imageCount,
    RenderPass : app.imguiPass,
    MSAASamples : app.getSampleCount(),
    CheckVkResultFn : &enforceVK
  };
  ImGui_ImplVulkan_Init(&imguiInit);
  if(app.verbose) SDL_Log("ImGui initialized");
}

ImDrawData* renderGUI(ref App app){
  // Start ImGui frame
  ImGui_ImplVulkan_NewFrame();
  ImGui_ImplSDL2_NewFrame();
  igNewFrame();
  if(app.showdemo) igShowDemoWindow(&app.showdemo);
  igPushFont(app.fonts[1]);
  igSetNextWindowPos(ImVec2(0.0f, 0.0f), 0, ImVec2(0.0f, 0.0f));
  auto flags = ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;
  igBegin("FPS", null, flags);
    igText("%s", app.properties.deviceName.ptr);
    igText("Vulkan v%d.%d.%d", VK_API_VERSION_MAJOR(app.properties.apiVersion),
                       VK_API_VERSION_MINOR(app.properties.apiVersion),
                       VK_API_VERSION_PATCH(app.properties.apiVersion));
    igText("%.1f FPS, %.1f ms", app.io.Framerate, 1000.0f / app.io.Framerate);
    igText("C: [%.1f, %.1f, %.1f]", app.camera.position[0], app.camera.position[1], app.camera.position[2]);
    igText("F: [%.1f, %.1f, %.1f]", app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2]);
  igEnd();
  igPopFont();

  igPushFont(app.fonts[0]);
  igBegin("All Objects", null, 0);
  igBeginTable("Objects", 3, 0, ImVec2(0.0f, 0.0f), 0.0f);
  foreach(i, object; app.objects){
    igTableNextRow(0, 5.0f);
    string text = to!string(i);
    if(object.name) text = object.name() ~ " " ~ text;
    igTableSetColumnIndex(0);
    igText(text.toStringz, ImVec2(0.0f, 0.0f));
    igTableSetColumnIndex(1);
    igPushID_Int(to!int(i));
    if(igButton((app.objects[i].isVisible?"Hide":"Show"), ImVec2(0.0f, 0.0f))){ 
      app.objects[i].isVisible = !app.objects[i].isVisible;
    }
    igSameLine(0,5);
    if(igButton("Delete", ImVec2(0.0f, 0.0f))){
      app.objects[i].deAllocate = true;
    }
    igTableSetColumnIndex(2);
    auto p = app.objects[i].position;
    igText(format("[%.1f %.1f %.1f]", p[0], p[1], p[2]).toStringz, ImVec2(0.0f, 0.0f));
    igPopID();
  }
  igEndTable();
  igEnd();
  igPopFont();

  igBegin("Vulkan Texture Test", null, 0);
  igText("pointer = %p", app.textures[4].descrSet);
  igText("size = %d x %d", app.textures[4].width, app.textures[5].height);
  igImage(cast(ImTextureID)app.textures[4].descrSet, ImVec2(app.textures[5].width/10, app.textures[5].height/10), ImVec2(0, 0), ImVec2(1, 1));
  igEnd();

  igRender();

  return(igGetDrawData());
}
