/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import imgui : faIcon;
import widgets : text, cstr;

size_t vertexCount(Geometry o, bool showBounds) {
  return o.vertices.length * o.instances.length + (showBounds && o.box ? o.box.vertices.length * o.box.instances.length : 0);
}

size_t indexCount(Geometry o, bool showBounds) {
  return o.indices.length * o.instances.length + (showBounds && o.box ? o.box.indices.length * o.box.instances.length : 0);
}

string humanCount(size_t n) {
  if (n >= 1_000_000) return format("%.1fM", n / 1_000_000.0);
  if (n >= 1_000) return format("%.1fK", n / 1_000.0);
  return format("%d", n);
}

void showTimingsContent(ref App app) {
  ulong total = 0;
  foreach(ms; app.timings) total += ms;
  foreach(name, ms; app.timings) {
    if(ms < 10) continue;
    igProgressBar(total ? cast(float)ms / total : 0.0f, ImVec2(60, igGetTextLineHeightWithSpacing()), "");
    igSameLine(0, 6);
    igText(cstr("%s %dms", name, ms));
  }
}

/** Show the GUI window with FPS statistics */
void showFPSContent(ref GameApp app, uint font = 0) {
  version(Android){
    igPushFont(app.gui.fonts[font], app.gui.fontsize(.8f));
  }else{
    igPushFont(app.gui.fonts[font], app.gui.fontsize());
  }
  ImVec2 size;
  igCalcTextSize(&size, "Hello", null, false, 0.0f);
  version(Android){
    igSetNextWindowPos(ImVec2(60.0f, size.y + 5.0f), 0, ImVec2(0.0f, 0.0f));
  }else{
    igSetNextWindowPos(ImVec2(0.0f, size.y + 5.0f), 0, ImVec2(0.0f, 0.0f));
  }
  auto flags = ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;
  igBegin("FPS", null, flags);
    igText("%s %s (v%d.%d.%d)", faIcon(), app.properties.deviceName.ptr,
                                VK_API_VERSION_MAJOR(app.properties.apiVersion),
                                VK_API_VERSION_MINOR(app.properties.apiVersion),
                                VK_API_VERSION_PATCH(app.properties.apiVersion));
    igText("%.1f FPS, %.1f ms", app.gui.io.Framerate, 1000.0f / app.gui.io.Framerate);
    igText("%d objects, %d textures", app.objects.length, app.textures.length);
    igText("%d/%d bones, %d/%d meshes", app.bones.length, app.boneOffsets.length, app.meshes.length, app.meshes.capacity);
    if("ClusterCounter" in app.buffers) {
      uint used = *cast(uint*)app.buffers["ClusterCounter"][0].data;
      uint cap = app.buffers["ClusterLights"].nObjects;
      text("Light clusters: %s / %s%s", humanCount(used), humanCount(cap), used > cap ? " OVERFLOW" : "");
    }
    auto iV = app.objects.map!(o => o.vertexCount(app.showBounds)).sum();
    auto iI = app.objects.map!(o => o.indexCount(app.showBounds)).sum();
    auto hV = app.objects.filter!(o => !o.isVisible || !o.inFrustum).map!(o => o.vertexCount(app.showBounds)).sum();
    auto hI = app.objects.filter!(o => !o.isVisible || !o.inFrustum).map!(o => o.indexCount(app.showBounds)).sum();
    text("Shown: %s/%s vertices, %s/%s indices", humanCount(iV - hV), humanCount(iV), humanCount(iI - hI), humanCount(iI));
    text("Shadow objects: %s / %s", humanCount(app.shadows.lastShadowInstances), humanCount(app.shadows.totalShadowInstances));
    igText("C: [%.1f, %.1f, %.1f]", app.camera.position[0], app.camera.position[1], app.camera.position[2]);
    igText("F: [%.1f, %.1f, %.1f]", app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2]);
    app.showTimingsContent();
  igEnd();
  igPopFont();
}

