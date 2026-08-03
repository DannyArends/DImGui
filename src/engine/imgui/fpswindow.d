/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : faIcon;
import vram : printVRAM;
import widgets : text;

/** Vertices submitted for an object: mesh × instances (+ bounds box when shown). */
size_t vertexCount(Geometry o, bool showBounds) {
  return o.vertices.length * o.instances.length + (showBounds && o.box ? o.box.vertices.length * o.box.instances.length : 0);
}

/** Indices submitted for an object: mesh × instances (+ bounds box when shown). */
size_t indexCount(Geometry o, bool showBounds) {
  return o.indices.length * o.instances.length + (showBounds && o.box ? o.box.indices.length * o.box.instances.length : 0);
}

/** Aggregate scene geometry counts (shown = visible & in-frustum). */
struct SceneStats { size_t shownV, totalV, shownI, totalI; }

/** Single pass over app.objects computing all four counts at once. */
SceneStats sceneStats(ref App app) {
  SceneStats s;
  foreach (o; app.objects) {
    immutable v = o.vertexCount(app.showBounds);
    immutable n = o.indexCount(app.showBounds);
    s.totalV += v; s.totalI += n;
    if (o.isVisible && o.inFrustum) { s.shownV += v; s.shownI += n; }
  }
  return s;
}

/** Geometry line — the O(objects) scan refreshes every REFRESH frames, not every frame. */
void showGeometryLine(ref App app) {
  enum int REFRESH = 15;
  static SceneStats cached;
  static int cooldown = 0;
  if (cooldown-- <= 0) { cached = app.sceneStats(); cooldown = REFRESH; }
  text("Shown: %s/%s vertices, %s/%s indices",
       humanCount(cached.shownV), humanCount(cached.totalV), humanCount(cached.shownI), humanCount(cached.totalI));
}

/** Light-cluster occupancy (exponential moving average), when the counter buffer exists. */
void showClusterLine(ref App app) {
  if ("ClusterCounter" !in app.buffers) return;
  static float avgClusters = 0;
  uint sample = *cast(uint*)app.buffers["ClusterCounter"][0].data;
  avgClusters += (sample - avgClusters) * 0.02f;
  uint cap = app.buffers["ClusterLights"].nObjects;
  text("Light clusters: %s / %s%s", humanCount(cast(uint)avgClusters), humanCount(cap), cast(uint)avgClusters > cap ? " OVERFLOW" : "");
}

/** Per-pass GPU timings as proportion bars (only passes above the threshold). */
void showTimingsContent(ref App app) {
  ulong total = 0;
  foreach (ms; app.timings) total += ms;
  foreach (name, ms; app.timings) {
    if (ms < MS_THRESHOLD) continue;
    igProgressBar(total ? cast(float)ms / total : 0.0f, ImVec2(60, igGetTextLineHeightWithSpacing()), "");
    igSameLine(0, 6);
    text("%s %dms", name, ms);
  }
}

/** Device / driver identity line. */
void showDeviceLine(ref App app) {
  igText("%s %s (v%d.%d.%d)", faIcon(), app.properties.deviceName.ptr,
         VK_API_VERSION_MAJOR(app.properties.apiVersion),
         VK_API_VERSION_MINOR(app.properties.apiVersion),
         VK_API_VERSION_PATCH(app.properties.apiVersion));
}

/** Shadow map activity line. */
void showShadowLine(ref App app) {
  text("Shadow maps: %s active, %s static rebuilt", app.shadows.activeShadowMaps, app.shadows.staticRebuilds);
  igSameLine(0, 4);
  text("(s/d %s/%s)", humanCount(app.shadows.staticShadowInstances), humanCount(app.shadows.dynamicShadowInstances));
}

/** Show the GUI window with FPS statistics */
void showFPSContent(ref App app, uint font = 0) {
  version(Android){ igPushFont(app.gui.fonts[font], app.gui.fontsize(.8f)); }
  else{ igPushFont(app.gui.fonts[font], app.gui.fontsize()); }

  ImVec2 size;
  igCalcTextSize(&size, "Hello", null, false, 0.0f);
  version(Android){ igSetNextWindowPos(ImVec2(60.0f, size.y + 5.0f), 0, ImVec2(0.0f, 0.0f)); }
  else{ igSetNextWindowPos(ImVec2(0.0f, size.y + 5.0f), 0, ImVec2(0.0f, 0.0f)); }

  auto flags = ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar
             | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;
  igBegin("FPS", null, flags);
    app.showDeviceLine();
    igText("%.1f FPS, %.1f ms", app.gui.io.Framerate, 1000.0f / app.gui.io.Framerate);
    igText("%d objects, %d textures", app.objects.length, app.textures.length);
    igText("%d bones, %d pose slots, %d/%d meshes", app.bones.length, app.boneOffsets.capacity, app.meshes.length, app.meshes.capacity);
    app.printVRAM();
    app.showClusterLine();
    app.showGeometryLine();
    app.showShadowLine();
    igText("C: [%.1f, %.1f, %.1f]", app.camera.position[0], app.camera.position[1], app.camera.position[2]);
    igText("F: [%.1f, %.1f, %.1f]", app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2]);
    if(app.verbose) app.showTimingsContent();
  igEnd();
  igPopFont();
}
