/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Show the GUI window with FPS statistics
 */
void showFPSwindow(ref App app, uint font = 1) {
  igPushFont(app.gui.fonts[font]);
  ImVec2 size;
  igCalcTextSize(&size, "Hello", null, false, 0.0f);

  igSetNextWindowPos(ImVec2(0.0f, size.y + 5.0f), 0, ImVec2(0.0f, 0.0f));
  auto flags = ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;
  igBegin("FPS", null, flags);
    igText("%s (v%d.%d.%d)", app.properties.deviceName.ptr,
                             VK_API_VERSION_MAJOR(app.properties.apiVersion),
                             VK_API_VERSION_MINOR(app.properties.apiVersion),
                             VK_API_VERSION_PATCH(app.properties.apiVersion));
    igText("%.1f FPS, %.1f ms", app.gui.io.Framerate, 1000.0f / app.gui.io.Framerate);
    igText("%d objects, %d textures", app.objects.length, app.textures.length);
    igText("C: [%.1f, %.1f, %.1f]", app.camera.position[0], app.camera.position[1], app.camera.position[2]);
    igText("F: [%.1f, %.1f, %.1f]", app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2]);
  igEnd();
  igPopFont();
}

