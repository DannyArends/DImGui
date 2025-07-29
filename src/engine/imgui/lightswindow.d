/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import lights : Light;

/** Show the GUI window which allows us to manipulate lighting
 */
void showLightswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBegin("Lights", show, 0)){
    igTableNextColumn();
    igText("Disco", ImVec2(0.0f, 0.0f)); igSameLine(0,5);
    igCheckbox("##disco", &app.disco);

    igBeginTable("Lights_Tbl", 2,  ImGuiTableFlags_Resizable, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, ref Light light; app.lights) {
      igPushID_Int(to!int(i));
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(format("light %d",i).toStringz, ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      //igBeginTable("Light_Tbl", 2,  ImGuiTableFlags_Resizable, ImVec2(0.0f, 0.0f), 0.0f);
        //igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Position".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##pX", ImGuiDataType_Float,  &light.position[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##pY", ImGuiDataType_Float,  &light.position[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##pZ", ImGuiDataType_Float,  &light.position[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);

        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Intensity".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##I0", ImGuiDataType_Float,  &light.intensity[0], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##I1", ImGuiDataType_Float,  &light.intensity[1], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##I2", ImGuiDataType_Float,  &light.intensity[2], &app.gui.col[0], &app.gui.col[1], "%.2f", 0);

        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Direction".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##D0", ImGuiDataType_Float,  &light.direction[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##D1", ImGuiDataType_Float,  &light.direction[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##D2", ImGuiDataType_Float,  &light.direction[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
        igTableNextRow(0, 5.0f);
        igTableNextColumn();
          igText("Cone Angle".toStringz, ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          igPushItemWidth(75 * app.gui.uiscale);
          igSliderScalar("##A0", ImGuiDataType_Float,  &light.properties[2], &app.gui.cone[0], &app.gui.cone[1], "%.2f", 0); igSameLine(0,5);
        //igEndTable();
      igPopID();
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}
