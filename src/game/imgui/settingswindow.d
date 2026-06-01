/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import imgui : clearSettings;
import lights : toggleLightGeometries;
import widgets : labelCol, setting, infoRow;

/** Show the GUI window with global settings */
void showSettingsContent(ref GameApp app, uint font = 0) {
  igBeginTable("Settings_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

  infoRow("Total Frames", "%s", app.totalFramesRendered);
  infoRow("Deletion Queues", "%d / %d / %d", app.bufferDeletionQueue.length, app.swapDeletionQueue.length, app.mainDeletionQueue.length);

  setting("Verbose", app.verbose, 0u, 2u, 100, app.gui.uiscale);

  labelCol("Lighting Mode");
    const(char)*[3] modes = ["Global Illumination", "Lights", "Lights + Shadows"];
    int lm = cast(int)app.lMode;
    igPushItemWidth(200 * app.gui.uiscale);
    if(igCombo_Str_arr("##lm", &lm, &modes[0], 3, -1)) app.lMode = cast(LMode)lm;
    igPopItemWidth();

  labelCol("Clear Settings"); if(igButton("RESET GUI", ImVec2(0.0f, 0.0f))) clearSettings();
  setting("Volume", app.soundEffectGain, app.gui.sound[0], app.gui.sound[1], 150, app.gui.uiscale);
  setting("God Mode", app.camera.godMode);
  if(setting("Show Lights", app.showLights)) app.toggleLightGeometries();
  setting("Disco Mode", app.disco);
  setting("Show Bounds", app.showBounds);
  setting("Show Paths", app.showPaths);
  setting("Show Rays", app.showRays);
  labelCol("Clear color"); igColorEdit3("##clearcolor", app.clearValue[0].color.float32.ptr, ImGuiColorEditFlags_Float);
  igEndTable();
}

