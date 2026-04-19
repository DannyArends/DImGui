/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import tileatlas : tileData, TileType;
import textures : ImTextureRefFromID, idx;
import imgui : faIcon;

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

void showInventoryContent(ref App app, uint font = 0) {
  if(app.inventory.length == 0) {
    igText("Empty", ImVec2(0.0f, 0.0f));
    return;
  }
  float cellSize = 48.0f;
  int cols = cast(int)((app.gui.panelW - 20) / (cellSize + 4));
  int col = 0;

  foreach (tileType, count; app.inventory) {
    if (count <= 0) continue;
    auto name = tileData[tileType].name;
    auto texIdx = idx(app.textures, name ~ "_base");
    if (texIdx < 0) continue;
    auto texID = ImTextureRefFromID(cast(ulong)app.textures[texIdx].imID);

    bool selected = app.inventory.selectedTile == tileType;
    if (selected) igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.4f, 0.6f, 0.4f, 1.0f));
    igImageButton(toStringz(format("##inv_%d", tileType)), texID,
                  ImVec2(cellSize, cellSize),
                  ImVec2(0.0f, 0.0f), ImVec2(1.0f, 1.0f),
                  ImVec4(0,0,0,0), ImVec4(1,1,1,1));
    if (igIsItemClicked(0)) app.inventory.selectedTile = selected ? TileType.None : tileType;
    if (selected) igPopStyleColor(1);

    ImVec2 pos, posMax;
    igGetItemRectMin(&pos);
    igGetItemRectMax(&posMax);
    drawCenteredText(igGetWindowDrawList(), pos, posMax, toStringz(format("%d", count)));

    if(igIsItemHovered(0)) igSetTooltip(toStringz(format("%s x%d", name, count)));

    col++;
    if(col < cols) igSameLine(0, 4);
    else { col = 0; igNewLine(); }
  }
  igNewLine();
}

