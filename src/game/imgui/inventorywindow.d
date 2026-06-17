/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import imgui : faIcon;
import textures : ImTextureRefFromID, idx;
import widgets : drawCenteredText, text;

/** Show inventory */
void showInventoryContent(ref GameApp app, uint font = 0) {
  float cellSize = 32.0f;
  int cols = cast(int)floor((app.gui.panelW - cellSize) / cast(float)(cellSize + 4)) - 1;
  int col = 0;

  foreach(tileType; EnumMembers!ResourceType) {
    if(!resourceData(tileType).buildable) continue;
    auto texIdx = idx(app.textures, resourceData(tileType).name ~ "_base");
    if(texIdx < 0) continue;
    auto texID = ImTextureRefFromID(cast(ulong)app.textures[texIdx].imID);
    int count = app.world.inventory.get(tileType, app);

    bool selected = app.world.inventory.type == tileType;
    if(selected) igPushStyleColor_Vec4(ImGuiCol_Button, ImVec4(0.4f, 0.6f, 0.4f, 1.0f));
    auto tint = count > 0 ? ImVec4(1,1,1,1) : ImVec4(0.3f,0.3f,0.3f,0.5f);
    igImageButton(cstr("##inv_%d", tileType), texID,
                  ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1),
                  ImVec4(0,0,0,0), tint);
    if(count > 0 && igIsItemClicked(0)) {
      app.world.inventory.type = selected ? ResourceType.None : tileType;
      app.world.inventory.activeTool = selected ? ToolMode.Select : ToolMode.Build;
    }
    if(selected) igPopStyleColor(1);

    ImVec2 pos, posMax;
    igGetItemRectMin(&pos);
    igGetItemRectMax(&posMax);
    if(count > 0) drawCenteredText(igGetWindowDrawList(), pos, posMax, cstr("%d", count));
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
      foreach(ref d; app.world.dwarves){ foreach(ref s; d.inventory){
        if(s.isStack && s.type == tileType) total += s.count;
      } }
    if(total == 0) continue;
    text("%s: %d", resourceData(tileType).name, total);
  }
}

