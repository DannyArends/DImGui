/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import textures : ImTextureRefFromID, idx;
import imgui : faIcon;

/** Show tool mode switcher */
void showToolSwitcher(ref App app) {
  immutable string[4] labels = [ " Select ", " Mine ", " Build ", " Stockpile " ];
  immutable ToolMode[4] modes = [ ToolMode.Select, ToolMode.Mine, ToolMode.Build, ToolMode.Stockpile ];
  foreach(i, mode; modes) {
    bool active = app.world.activeTool == mode;
    if(active) igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.3f, 0.6f, 0.3f, 1.0f));
    if(igButton(toStringz(labels[i]), ImVec2(0, 0))) app.world.activeTool = mode;
    if(active) igPopStyleColor(1);
    if(i < modes.length - 1) igSameLine(0, 4);
  }
  igSeparator();
}

void drawCenteredText(ImDrawList* drawList, ImVec2 min, ImVec2 max, const(char)* text) {
  auto font = igGetFont();
  float fontSize = igGetFontSize();
  ImVec2 textSize;
  igCalcTextSize(&textSize, text, null, false, -1.0f);
  float tx = min.x + (max.x - min.x - textSize.x) * 0.5f;
  float ty = min.y + (max.y - min.y - textSize.y) * 0.5f;
  ImDrawList_PushClipRectFullScreen(drawList);
  foreach (off; [ImVec2(-1,-1), ImVec2(1,-1), ImVec2(-1,1), ImVec2(1,1)]) {
    ImDrawList_AddText_FontPtr(drawList, font, fontSize, ImVec2(tx+off.x, ty+off.y), 0xFF000000, text, null, 0.0f, null);
  }
  ImDrawList_AddText_FontPtr(drawList, font, fontSize, ImVec2(tx, ty), 0xFFFFFFFF, text, null, 0.0f, null);
  ImDrawList_PopClipRect(drawList);
}

/** Show inventory */
void showInventoryContent(ref App app, uint font = 0) {
  app.showToolSwitcher();

  float cellSize = 32.0f;
  int cols = cast(int)floor((app.gui.panelW - cellSize) / cast(float)(cellSize + 4)) - 1;
  int col = 0;

  foreach(tileType; EnumMembers!ResourceType) {
    if(!resourceData(tileType).buildable) continue;
    auto texIdx = idx(app.textures, resourceData(tileType).name ~ "_base");
    if(texIdx < 0) continue;
    auto texID = ImTextureRefFromID(cast(ulong)app.textures[texIdx].imID);
    int count = app.world.inventory.get(tileType, app);

    bool selected = app.world.inventory.ghost.type == tileType;
    if(selected) igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.4f, 0.6f, 0.4f, 1.0f));
    auto tint = count > 0 ? ImVec4(1,1,1,1) : ImVec4(0.3f,0.3f,0.3f,0.5f);
    igImageButton(toStringz(format("##inv_%d", tileType)), texID,
                  ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1),
                  ImVec4(0,0,0,0), tint);
    if(count > 0 && igIsItemClicked(0)) app.world.inventory.ghost.type = selected ? ResourceType.None : tileType;
    if(selected) igPopStyleColor(1);

    ImVec2 pos, posMax;
    igGetItemRectMin(&pos);
    igGetItemRectMax(&posMax);
    if(count > 0) drawCenteredText(igGetWindowDrawList(), pos, posMax, toStringz(format("%d", count)));
    if(igIsItemHovered(0)) igSetTooltip(toStringz(app.world.inventory.toString(tileType, app)));
    if(++col < cols) igSameLine(0, 4);
    else { col = 0; }
  }
  igSeparator();
  igText("Items:");
  foreach(tileType; EnumMembers!ResourceType) {
    if(resourceData(tileType).maxStack <= 1) continue;
    uint total = 0;
    if(app.world.dwarves !is null)
      foreach(ref d; app.world.dwarves)
        foreach(ref s; d.inventory)
          if(s.isStack && s.type == tileType) total += s.count;
    if(total == 0) continue;
    igText(toStringz(format("%s: %d", resourceData(tileType).name, total)));
  }
}

