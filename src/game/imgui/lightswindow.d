/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import imgui : iconText;
import lights : Light, updateSun, sunElevation, sunAzimuth;
import widgets : setting, sliderFloat3, infoRow;

/** Show the GUI window which allows us to manipulate lighting */
void showLightsContent(ref GameApp app, uint font = 0) {
  auto lightsBefore = app.lights.lights.dup;

  igCheckbox(iconText(cast(string)ICON_FA_MUSIC, "Disco"), &app.disco);

  igBeginTable("Sun_Tbl", 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
  setting("Time of Day", app.lights.sunTime, 0.0f, 24.0f, 200, app.gui.uiscale, "%.1f h");
  setting("Bearing", app.lights.sunBearing, 0.0f, 365.0f, 200, app.gui.uiscale, "%.0f");
  infoRow("Elevation", "%.1f deg", sunElevation(app.lights.sunTime));
  infoRow("Azimuth", "%.1f deg", sunAzimuth(app.lights.sunTime));
  igEndTable();

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
    if(igTreeNodeEx_Str(iconText(cast(string)ICON_FA_LIGHTBULB, format("Light %d", i)), 0)) {
      igBeginTable(toStringz(format("Light_Tbl_%d", i)), 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

      igTableNextColumn(); igText(iconText("Position", cast(string)ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT));
      igTableNextColumn();
        sliderFloat3(["##pX","##pY","##pZ"], &light.position[0], &light.position[1], &light.position[2], 
                     &app.gui.pos[0], &app.gui.pos[1], 75, app.gui.uiscale);

      igTableNextColumn(); igText(iconText("Intensity", cast(string)ICON_FA_BOLT));
      igTableNextColumn();
        sliderFloat3(["##I0","##I1","##I2"], &light.intensity[0], &light.intensity[1], &light.intensity[2], 
                     &app.gui.col[0], &app.gui.col[1], 75, app.gui.uiscale);


      igTableNextColumn(); igText(iconText("Direction", cast(string)ICON_FA_LOCATION_ARROW));
      igTableNextColumn();
        sliderFloat3(["##D0","##D1","##D2"], &light.direction[0], &light.direction[1], &light.direction[2], 
                     &app.gui.pos[0], &app.gui.pos[1], 75, app.gui.uiscale);

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

