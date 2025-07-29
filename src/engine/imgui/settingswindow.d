/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : clearSettings;

/** Show the GUI window with global settings
 */
void showSettingswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBegin("Settings", show, 0)){
    igBeginTable("Settings_Tbl", 2,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    igTableNextColumn();
    igText("Total Frames", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igText(toStringz(format("%s", app.totalFramesRendered)), ImVec2(0.0f, 0.0f));

    igTableNextColumn();
    igText("Deletion Queues", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igText(toStringz(format("%d / %d / %d", app.bufferDeletionQueue.length, app.swapDeletionQueue.length, app.mainDeletionQueue.length)), ImVec2(0.0f, 0.0f));

    igTableNextColumn();
    igText("Verbose", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    igPushItemWidth(100 * app.gui.uiscale);
      int[2] limits = [0, 2];
      igSliderScalar("##a", ImGuiDataType_U32,  &app.verbose, &limits[0], &limits[1], "%d", 0);

    igTableNextColumn();
    igText("Clear Settings", ImVec2(0.0f, 0.0f)); igTableNextColumn();
    if(igButton("RESET GUI", ImVec2(0.0f, 0.0f))){ clearSettings(); }

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
    igPushItemWidth(100 * app.gui.uiscale);
    igSliderScalar("##colR", ImGuiDataType_Float,  &app.clearValue[0].color.float32[0], &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);igSameLine(0,5);
    igPushItemWidth(100 * app.gui.uiscale);
    igSliderScalar("##colG", ImGuiDataType_Float,  &app.clearValue[0].color.float32[1], &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);igSameLine(0,5);
    igPushItemWidth(100 * app.gui.uiscale);
    igSliderScalar("##colB", ImGuiDataType_Float,  &app.clearValue[0].color.float32[2], &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);

    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

