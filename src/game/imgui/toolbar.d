/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import color : asIm;
import imgui : faIcon;
import sfx : play;
import tool : tools, setActiveTool;

/** DF-style icon tool bar: bottom edge in landscape, left edge in portrait. Avoids the side panel. */
void showToolbar(ref GameApp app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  float btn = app.gui.fontsize * 2.0f;
  immutable ImVec4 gray = ImVec4(0.55f, 0.55f, 0.55f, 1.0f);

  auto flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize  | ImGuiWindowFlags_NoBringToFrontOnFocus |
               ImGuiWindowFlags_NoNavInputs | ImGuiWindowFlags_NoNavFocus | ImGuiWindowFlags_AlwaysAutoResize;
  float dispW = app.gui.io.DisplaySize.x, dispH = app.gui.io.DisplaySize.y;
  bool landscape = dispW > dispH;

  if(landscape && !isAndroid) { // bottom-centred over the play area (left of the side panel)
    igSetNextWindowPos(ImVec2((dispW - app.gui.panelW) * 0.5f, dispH), ImGuiCond_Always, ImVec2(0.5f, 1.0f));
  } else {        // left edge, centred between the menu bar and the bottom panel
    igSetNextWindowPos(ImVec2(0, (app.gui.menuH + (dispH - app.gui.panelH)) * 0.5f), ImGuiCond_Always, ImVec2(0.0f, 0.5f));
  }

  igBegin("##toolbar", null, flags);
  if(app.world.inventory.activeTool == ToolMode.Build) {
    app.buildSubBar(btn, gray);                     // Build is modal: the bar becomes the build menu
  } else {
    app.mainTools(btn, gray, landscape && !isAndroid);
  }
  igEnd();
  igPopFont();
}

/** The normal tool row. */
private void mainTools(ref GameApp app, float btn, ImVec4 gray, bool sameline) {
  foreach(i, ref t; tools) {
    bool sel = (app.world.inventory.activeTool == t.mode);
    igPushStyleColor_Vec4(ImGuiCol_Button, sel ? t.color.asIm() : gray);
    igPushStyleColor_Vec4(ImGuiCol_ButtonActive, sel ? t.color.asIm() : gray);
    igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, t.color.asIm());
    if(igButton(faIcon(t.icon), ImVec2(btn, btn))) {
      app.setActiveTool(t.mode);
      app.world.inventory.type = ResourceType.None;
      app.play("DM-CGS-31", 0.1f);
    }
    igPopStyleColor(3);
    if(sameline && i < tools.length - 1) igSameLine(0, 4);
  }
}

/** Build mode: Back, then Landscaping + one labelled row per workshop. Vertical, so it works in any orientation. */
private void buildSubBar(ref GameApp app, float btn, ImVec4 gray) {
  immutable ImVec4 accent = Colors.dodgerblue.asIm();

  if(app.buildRow(cast(string)ICON_FA_ARROW_LEFT, "Back", false, gray, accent, -1)) {
    app.setActiveTool(isAndroid ? ToolMode.Info : ToolMode.Select);
    return;
  }
  igSeparator();

  if(app.buildRow(cast(string)ICON_FA_MOUND, "Landscaping", app.world.inventory.placingWorkshop.length == 0, gray, accent, 0))
    app.world.inventory.placingWorkshop = "";

  foreach(i, ref w; workshopTable) {
    bool sel = (app.world.inventory.placingWorkshop == w.name);
    if(app.buildRow(faForName(w.icon), w.name, sel, gray, accent, cast(int)i + 1))
      app.world.inventory.placingWorkshop = w.name;
  }
}

/** One full-width icon+label row; highlighted when selected. Returns true when clicked. */
private bool buildRow(ref GameApp app, string glyph, string label, bool sel, ImVec4 gray, ImVec4 accent, int id) {
  igPushID_Int(id);
  igPushStyleColor_Vec4(ImGuiCol_Button, sel ? accent : gray);
  igPushStyleColor_Vec4(ImGuiCol_ButtonActive, sel ? accent : gray);
  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, accent);
  bool hit = igButton(cstr("%s  %s", glyph, label), ImVec2(app.gui.fontsize * 9.0f, 0));   // fixed width => aligned rows
  igPopStyleColor(3);
  igPopID();
  return hit;
}

/** Resolve a workshop raw's icon name to its FontAwesome glyph. */
private string faForName(string name) {
  switch(name) {
    case "HAMMER":             return cast(string)ICON_FA_HAMMER;
    case "SCREWDRIVER_WRENCH": return cast(string)ICON_FA_SCREWDRIVER_WRENCH;
    case "MOUND":              return cast(string)ICON_FA_MOUND;
    default:                   return cast(string)ICON_FA_HAMMER;
  }
}