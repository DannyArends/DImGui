/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : clearSettings;
import lights : toggleLightGeometries;
import widgets : labelCol;

/** Show the GUI window with global settings */
void showSettingsContent(ref App app, uint font = 0) {
  igBeginTable("Settings_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

  labelCol("Total Frames"); igText(toStringz(format("%s", app.totalFramesRendered)));
  labelCol("Deletion Queues"); igText(toStringz(format("%d / %d / %d", app.bufferDeletionQueue.length, app.swapDeletionQueue.length, app.mainDeletionQueue.length)));

  labelCol("Verbose");
    int[2] limits = [0, 2];
    igPushItemWidth(100 * app.gui.uiscale);
    igSliderScalar("##a", ImGuiDataType_U32, &app.verbose, &limits[0], &limits[1], "%d", 0);

  labelCol("Lighting Mode");
    const(char)*[3] modes = ["Global Illumination", "Lights", "Lights + Shadows"];
    int lm = cast(int)app.lMode;
    igPushItemWidth(200 * app.gui.uiscale);
    if(igCombo_Str_arr("##lm", &lm, &modes[0], 3, -1)) app.lMode = cast(LMode)lm;
    igPopItemWidth();

  labelCol("Clear Settings"); if(igButton("RESET GUI", ImVec2(0.0f, 0.0f))) clearSettings();
  labelCol("Volume"); igSliderScalar("##", ImGuiDataType_Float, &app.soundEffectGain, &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);
  labelCol("God Mode"); igCheckbox("##godMode", &app.camera.godMode);
  labelCol("Show Lights"); if(igCheckbox("##showLights", &app.showLights)) app.toggleLightGeometries();
  labelCol("Disco Mode"); igCheckbox("##disco", &app.disco);
  labelCol("Show Bounds"); igCheckbox("##showBounds", &app.showBounds);
  labelCol("Show Paths");  igCheckbox("##showPaths", &app.showPaths);
  labelCol("Show Rays"); igCheckbox("##showRays", &app.showRays);
  labelCol("Clear color"); igColorEdit3("##clearcolor", app.clearValue[0].color.float32.ptr, ImGuiColorEditFlags_Float);
  igEndTable();
}

