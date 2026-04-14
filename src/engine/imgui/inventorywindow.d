/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import tileatlas : tileData, TileType;
import textures : ImTextureRefFromID, idx;
import imgui : faIcon;

void drawCenteredText(ImDrawList* drawList, ImVec2 min, ImVec2 max, const(char)* text) {
  auto currentFont = igGetFont();
  float fontSize = igGetFontSize();
  ImVec2 textSize;
  igCalcTextSize(&textSize, text, null, false, -1.0f);
  float tx = min.x + (max.x - min.x - textSize.x) * 0.5f;
  float ty = min.y + (max.y - min.y - textSize.y) * 0.5f;
  ImDrawList_PushClipRectFullScreen(drawList);
  ImDrawList_AddText_FontPtr(drawList, currentFont, fontSize, ImVec2(tx-1, ty-1), 0xFF000000, text, null, 0.0f, null);
  ImDrawList_AddText_FontPtr(drawList, currentFont, fontSize, ImVec2(tx+1, ty-1), 0xFF000000, text, null, 0.0f, null);
  ImDrawList_AddText_FontPtr(drawList, currentFont, fontSize, ImVec2(tx-1, ty+1), 0xFF000000, text, null, 0.0f, null);
  ImDrawList_AddText_FontPtr(drawList, currentFont, fontSize, ImVec2(tx+1, ty+1), 0xFF000000, text, null, 0.0f, null);
  ImDrawList_AddText_FontPtr(drawList, currentFont, fontSize, ImVec2(tx,   ty  ), 0xFFFFFFFF, text, null, 0.0f, null);
  ImDrawList_PopClipRect(drawList);
}

void showInventoryContent(ref App app, uint font = 0) {
  if(app.inventory.length == 0) {
    igText("Empty", ImVec2(0.0f, 0.0f));
    return;
  }

  auto atlasIdx = idx(app.textures, "3DTextures");
  if(atlasIdx < 0) return;
  auto atlasID = ImTextureRefFromID(cast(ulong)app.textures[atlasIdx].imID);
  float atlasSize = cast(float)app.tileAtlas.size;
  float cellSize = 48.0f;
  int cols = cast(int)((app.gui.panelW - 20) / (cellSize + 4));
  int col = 0;

  foreach(tileType, count; app.inventory) {
    if(count <= 0) continue;
    auto name = tileData[tileType].name;
    if(name !in app.tileAtlas.uv) continue;
    auto uv = app.tileAtlas.uv[name];
    ImVec2 uv0 = ImVec2(uv[0][0] / atlasSize, uv[1][0] / atlasSize);
    ImVec2 uv1 = ImVec2(uv[0][1] / atlasSize, uv[1][1] / atlasSize);

    bool selected = app.inventory.selectedTile == tileType;
    if(selected) igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.4f, 0.6f, 0.4f, 1.0f));
    igImageButton(toStringz(format("##inv_%d", tileType)), atlasID, ImVec2(cellSize, cellSize), uv0, uv1, ImVec4(0,0,0,0), ImVec4(1,1,1,1));
    if(igIsItemClicked(0)) app.inventory.selectedTile = selected ? TileType.None : tileType;
    if(selected) igPopStyleColor(1);

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

