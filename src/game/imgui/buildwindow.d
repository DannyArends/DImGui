/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import imgui : faIcon;
import textures : ImTextureRefFromID, idx;
import widgets : drawCenteredText, text;
import jobs : jobQueue, buildingJob;

/** Build-type picker: pick rows (none picked = all), click a block type, queue the jobs. */
void showBuildContent(ref GameApp app, uint font = 0) {
  if(!app.world.inventory.showBuildWindow) return;

  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  float dispW = app.gui.io.DisplaySize.x, dispH = app.gui.io.DisplaySize.y;
  igSetNextWindowPos(ImVec2(dispW * 0.5f, dispH * 0.5f), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
  igSetNextWindowSize(ImVec2(360, 380), ImGuiCond_Appearing);
  igBegin(cstr("%s Build (%d)", fromStringz(faIcon(cast(string)ICON_FA_TROWEL)), app.world.inventory.buildSelection.length),
          &app.world.inventory.showBuildWindow, 0);

  // --- Rows: click to (de)select; none selected = apply to all ---
  igText("Tiles (none selected = all):".toStringz);
  foreach(i, ref b; app.world.inventory.buildSelection) {
    auto name = b.type == ResourceType.None ? "—" : resourceData(b.type).name;
    if(igSelectable_Bool(cstr("[%d,%d,%d]  %s##r%d", b.tile[0], b.tile[1], b.tile[2], name, i),
                         b.selected, 0, ImVec2(0, 0)))
      b.selected = !b.selected;
  }

  igSeparator();

  // --- One type grid (mirrors the inventory palette) ---
  igText("Assign type:".toStringz);
  float cellSize = 32.0f;
  int col = 0, cols = 7;
  foreach(tileType; EnumMembers!ResourceType) {
    if(!resourceData(tileType).buildable) continue;
    auto texIdx = idx(app.textures, resourceData(tileType).name ~ "_base");
    if(texIdx < 0) continue;
    auto texID = ImTextureRefFromID(cast(ulong)app.textures[texIdx].imID);
    int count = app.world.inventory.get(tileType, app);
    auto tint = count > 0 ? ImVec4(1,1,1,1) : ImVec4(0.3f,0.3f,0.3f,0.5f);

    igImageButton(cstr("##bt_%d", tileType), texID, ImVec2(cellSize, cellSize),
                  ImVec2(0,0), ImVec2(1,1), ImVec4(0,0,0,0), tint);
    if(igIsItemClicked(0)) {
      bool any = false;
      foreach(ref b; app.world.inventory.buildSelection) if(b.selected) { any = true; break; }
      foreach(ref b; app.world.inventory.buildSelection) if(!any || b.selected) b.type = tileType;
    }
    ImVec2 pos, posMax; igGetItemRectMin(&pos); igGetItemRectMax(&posMax);
    drawCenteredText(igGetWindowDrawList(), pos, posMax, cstr("%d", count));
    if(igIsItemHovered(0)) igSetTooltip(toStringz(app.world.inventory.toString(tileType, app)));
    if(++col < cols) igSameLine(0, 4); else col = 0;
  }

  igSeparator();
  if(igButton("Place".toStringz, ImVec2(0,0))) {
    foreach(ref b; app.world.inventory.buildSelection)
      if(b.type != ResourceType.None) jobQueue ~= buildingJob(b.tile, b.type);
    app.world.inventory.buildSelection = [];
    app.world.inventory.showBuildWindow = false;
  }
  igSameLine(0, 6);
  if(igButton("Cancel".toStringz, ImVec2(0,0))) {
    app.world.inventory.buildSelection = [];
    app.world.inventory.showBuildWindow = false;
  }

  igEnd();
  igPopFont();
}
