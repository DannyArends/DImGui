/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : iconText;
import lights : Light, updateSun, sunElevation, sunAzimuth;
import quaternion : w;

/** Show the GUI window which allows us to manipulate lighting
 */
void showLightsContent(ref App app, uint font = 0) {
  auto lightsBefore = app.lights.lights.dup;

  igCheckbox(iconText(cast(string)ICON_FA_MUSIC, "Disco"), &app.disco);

  if(igTreeNodeEx_Str(iconText(cast(string)ICON_FA_SUN_O, "Sun"), 0)) {
    igBeginTable("Sun_Tbl", 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

    igTableNextColumn(); igText("Time of Day");
    igTableNextColumn();
      igPushItemWidth(200 * app.gui.uiscale);
      igSliderFloat("##tod", &app.lights.sunTime, 0.0f, 24.0f, "%.1f h", 0);
    igTableNextColumn(); igText("Bearing");
    igTableNextColumn();
      igPushItemWidth(200 * app.gui.uiscale);
      igSliderFloat("##bear", &app.lights.sunBearing, 0.0f, 365.0f, "%.0f", 0);
    app.updateSun();

    igTableNextColumn(); igText("Elevation");
    igTableNextColumn();
      igText(toStringz(format("%.1f deg", sunElevation(app.lights.sunTime))));

    igTableNextColumn(); igText("Azimuth");
    igTableNextColumn();
      igText(toStringz(format("%.1f deg", sunAzimuth(app.lights.sunTime))));

    igEndTable();
    igTreePop();
  }

  foreach(i, ref Light light; app.lights) {
    if(i == 0) continue;
    igPushID_Int(to!int(i));
    bool enabled = app.lights[i].enabled();
    if(igCheckbox("##enabled", &enabled)) {
      app.lights[i].enabled(enabled);
      app.buffers["LightMatrices"].dirty[] = true;
      app.shadows.dirty = true;
    }
    igSameLine(0, 5);
    if(igTreeNodeEx_Str(iconText(cast(string)ICON_FA_LIGHTBULB_O, format("Light %d", i)), 0)) {
      igBeginTable(toStringz(format("Light_Tbl_%d", i)), 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

      igTableNextColumn(); igText(iconText("Position", cast(string)ICON_FA_ARROWS));
      igTableNextColumn();
        igPushItemWidth(75 * app.gui.uiscale); 
        igSliderScalar("##pX", ImGuiDataType_Float, &light.position[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##pY", ImGuiDataType_Float, &light.position[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##pZ", ImGuiDataType_Float, &light.position[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);

      igTableNextColumn(); igText(iconText("Intensity", cast(string)ICON_FA_BOLT));
      igTableNextColumn();
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##I0", ImGuiDataType_Float, &light.intensity[0], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##I1", ImGuiDataType_Float, &light.intensity[1], &app.gui.col[0], &app.gui.col[1], "%.2f", 0); igSameLine(0,5);
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##I2", ImGuiDataType_Float, &light.intensity[2], &app.gui.col[0], &app.gui.col[1], "%.2f", 0);

      igTableNextColumn(); igText(iconText("Direction", cast(string)ICON_FA_LOCATION_ARROW));
      igTableNextColumn();
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##D0", ImGuiDataType_Float, &light.direction[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##D1", ImGuiDataType_Float, &light.direction[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0); igSameLine(0,5);
        igPushItemWidth(75 * app.gui.uiscale);
        igSliderScalar("##D2", ImGuiDataType_Float, &light.direction[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);

      igTableNextColumn(); igText(iconText("Cone", cast(string)ICON_FA_EXPAND));
      igTableNextColumn();
        igPushItemWidth(75 * app.gui.uiscale); igSliderScalar("##A0", ImGuiDataType_Float, &light.properties[2], &app.gui.cone[0], &app.gui.cone[1], "%.2f", 0);

      igEndTable();
      igTreePop();
    }
    igPopID();
  }
  if(igIsAnyItemActive()) app.shadows.dirty = true;
  if(app.lights.lights != lightsBefore) { app.buffers["LightMatrices"].dirty[] = true; }
}

