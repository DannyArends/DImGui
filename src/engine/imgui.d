/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.conv : to;
import std.format : format;
import std.string : toStringz;

import geometry : position;

void initializeImGui(ref App app){
  igCreateContext(null);
  app.io = igGetIO_Nil();
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
  //igSetNextWindowPos(ImVec2(0, app.io.DisplaySize.y - 40), ImGuiCond_Always, ImVec2(0.0f,0.0f));
  igBegin("Main Menu", null, 0);
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
  igRender();

  return(igGetDrawData());
}
