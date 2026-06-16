/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import color : asIm;
import imgui : faIcon;
import tool : tools;

/** DF-style icon tool bar: bottom edge in landscape, left edge in portrait. Avoids the side panel. */
void showToolbar(ref GameApp app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);

  immutable ImVec4 unselected = ImVec4(0.55f, 0.55f, 0.55f, 1.0f);  // gray

  auto flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize  | ImGuiWindowFlags_NoBringToFrontOnFocus |
               ImGuiWindowFlags_NoNavInputs | ImGuiWindowFlags_NoNavFocus | ImGuiWindowFlags_AlwaysAutoResize;
  float dispW = app.gui.io.DisplaySize.x, dispH = app.gui.io.DisplaySize.y;
  bool landscape = dispW > dispH;

  if(landscape) { // bottom-centred over the play area (left of the side panel)
    igSetNextWindowPos(ImVec2((dispW - app.gui.panelW) * 0.5f, dispH), ImGuiCond_Always, ImVec2(0.5f, 1.0f));
  } else {        // left edge, centred between the menu bar and the bottom panel
    igSetNextWindowPos(ImVec2(0, (app.gui.menuH + (dispH - app.gui.panelH)) * 0.5f), ImGuiCond_Always, ImVec2(0.0f, 0.5f));
  }

  igBegin("##toolbar", null, flags);
  foreach(i, ref t; tools) {
    igPushStyleColor_Vec4(ImGuiCol_Button, (app.world.inventory.activeTool == t.mode) ? t.color.asIm() : unselected);
    igPushStyleColor_Vec4(ImGuiCol_ButtonActive, (app.world.inventory.activeTool == t.mode) ? t.color.asIm() : unselected);
    igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, t.color.asIm());
    if(igButton(faIcon(t.icon), ImVec2(36, 36))) {
      app.world.inventory.activeTool = t.mode;
      app.world.inventory.type = ResourceType.None;
    }
    igPopStyleColor(3);
    if(landscape && i < tools.length - 1) igSameLine(0, 4);
  }
  igEnd();
  igPopFont();
}
