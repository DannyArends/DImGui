/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : iconText, iconTextStr;
import lights : Light, updateSun, sunElevation, sunAzimuth;
import shadow : NUM_CASCADES;
import widgets : colValue, setting, text, sliderFloat3, infoRow, labelCol;

/** Show the GUI window which allows us to manipulate lighting */
void showLightsContent(ref App app, uint font = 0) {
  auto lightsBefore = app.lights.lights.dup;

  igCheckbox(iconText(cast(string)ICON_FA_MUSIC, "Disco"), &app.disco);

  foreach(i, ref Light light; app.lights) {
    igPushID_Int(to!int(i));
    bool enabled = app.lights[i].enabled();
    if(igCheckbox("##enabled", &enabled)) {
      app.lights[i].enabled(enabled);
      app.buffers["LightMatrices"].invalidate();
      app.lights.staticDirty = true;
    }
    igSameLine(0, 5);
    if(igTreeNodeEx_Str(iconText(cast(string)ICON_FA_LIGHTBULB, (i == 0)?"Sun":format("Light %d", i)), 0)) {
      if(igBeginTable(cstr("Light_Tbl_%d", i), 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
        int first = cast(int)light.cull[1];
        if(light.directional) {
          setting("Time of Day", app.lights.sunTime, 0.0f, 24.0f, 200, app.gui.uiscale, "%.1f h");
          setting("Bearing", app.lights.sunBearing, 0.0f, 365.0f, 200, app.gui.uiscale, "%.0f");
          infoRow("Elevation x Azimuth", "%.1f x %.1f deg", sunElevation(app.lights.sunTime), sunAzimuth(app.lights.sunTime));
          if(first >= 0) { foreach(c; 0 .. NUM_CASCADES) {
            float r = app.shadows.cascadeRadius[c];
            float texel = (r > 0.0f) ? (2.0f * r / cast(float)app.shadows.dimension) : 0.0f;
            infoRow(iconTextStr(format("Cascade %d", c), cast(string)ICON_FA_LAYER_GROUP), "%dx%d  r=%.0f texel=%.4f",
                    app.shadows[first + c].extent.width, app.shadows[first + c].extent.height, r, texel);
          } }
        } else {
          labelCol(iconText("Position", cast(string)ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT));
          sliderFloat3(["##pX","##pY","##pZ"], &light.position[0], &light.position[1], &light.position[2], 
                       &app.gui.pos[0], &app.gui.pos[1], 75, app.gui.uiscale);

          labelCol(iconText("Intensity", cast(string)ICON_FA_BOLT));
          sliderFloat3(["##I0","##I1","##I2"], &light.intensity[0], &light.intensity[1], &light.intensity[2], 
                       &app.gui.col[0], &app.gui.col[1], 75, app.gui.uiscale);

          labelCol(iconText("Direction", cast(string)ICON_FA_LOCATION_ARROW));
          sliderFloat3(["##D0","##D1","##D2"], &light.direction[0], &light.direction[1], &light.direction[2], 
                       &app.gui.one[0], &app.gui.one[1], 75, app.gui.uiscale);

          labelCol(iconText("Cone", cast(string)ICON_FA_EXPAND));
          app.colValue("##A0", &light.properties[2], app.gui.cone[0], app.gui.cone[1]);
        }
        if(first >= 0) {
          infoRow(iconTextStr("", cast(string)ICON_FA_SUN), "Casting %dx%d", app.shadows[first].extent.width, app.shadows[first].extent.height);
        }else{infoRow(iconTextStr("", cast(string)ICON_FA_MOON), "%s", "Evicted"); }
        igEndTable();
      }
      igTreePop();
    }
    igPopID();
  }
  if(app.lights.lights != lightsBefore) { app.buffers["LightMatrices"].invalidate(); }
}

