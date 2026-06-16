/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import ghost : syncBuildGhosts;
import imgui : faIcon;
import textures : ImTextureRefFromID, idx;
import widgets : drawCenteredText, text;
import jobs : jobQueue, buildingJob;
import inventory : deriveInventory;

/** Queue one buildingJob for the next unassigned tile (source -> sync order). */
private void assignNextBuild(ref GameApp app, ResourceType type) {
  foreach(ref b; app.world.inventory.buildSelection) {
    if(b.type != ResourceType.None) continue;
    b.type = type;
    jobQueue ~= buildingJob(b.tile, type);
    app.deriveInventory();    // lowers get(type)
    app.syncBuildGhosts();
    return;
  }
}

/** Cancel the whole build: remove its queued building jobs and close. */
private void cancelBuild(ref GameApp app) {
  bool[int[3]] tiles;
  foreach(ref b; app.world.inventory.buildSelection) if(b.type != ResourceType.None) tiles[b.tile] = true;
  jobQueue = jobQueue.filter!(j => !(j.name == "Building" && (j.targetTile in tiles) !is null)).array;
  app.world.inventory.buildSelection = [];
  app.world.inventory.showBuildWindow = false;
  app.deriveInventory();
  app.syncBuildGhosts();
}

/** Build picker: list of tiles + available types; click a type to queue the next tile. */
void showBuildContent(ref GameApp app, uint font = 0) {
  if(!app.world.inventory.showBuildWindow) return;

  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  float dispW = app.gui.io.DisplaySize.x, dispH = app.gui.io.DisplaySize.y;
  igSetNextWindowPos(ImVec2(dispW * 0.5f, dispH * 0.5f), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
  igSetNextWindowSize(ImVec2(300, 360), ImGuiCond_Appearing);

  int remaining = 0;
  foreach(ref b; app.world.inventory.buildSelection){ if(b.type == ResourceType.None){ remaining++; } }

  igBegin(cstr("%s Build##buildsel", fromStringz(faIcon(cast(string)ICON_FA_TROWEL))), &app.world.inventory.showBuildWindow, 0);
  text("Remaining: %d / %d", remaining, app.world.inventory.buildSelection.length);

  igText("Click to queue next:".toStringz);

  // Available types ONLY (count > 0) — clicking queues + lowers count
  float cellSize = 32.0f;
  int col = 0, cols = 6;
  foreach(tileType; EnumMembers!ResourceType) {
    if(!resourceData(tileType).buildable) continue;
    int count = app.world.inventory.get(tileType, app);                       if(count <= 0) continue;
    auto texIdx = idx(app.textures, resourceData(tileType).name ~ "_base");   if(texIdx < 0) continue;
    auto texID = ImTextureRefFromID(cast(ulong)app.textures[texIdx].imID);

    igImageButton(cstr("##bt_%d", tileType), texID, ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1), ImVec4(0,0,0,0), ImVec4(1,1,1,1));
    if(igIsItemClicked(0) && remaining > 0) app.assignNextBuild(tileType);
    ImVec2 pos, posMax; igGetItemRectMin(&pos); igGetItemRectMax(&posMax);
    drawCenteredText(igGetWindowDrawList(), pos, posMax, cstr("%d", count));
    if(igIsItemHovered(0)) igSetTooltip(toStringz(app.world.inventory.toString(tileType, app)));
    if(++col < cols) igSameLine(0, 4); else col = 0;
  }
  igNewLine();
  if(igButton("Cancel".toStringz, ImVec2(0,0))) app.cancelBuild();

  // Auto-close once every tile has a type
  int left = 0;
  foreach(ref b; app.world.inventory.buildSelection) if(b.type == ResourceType.None) left++;
  if(app.world.inventory.buildSelection.length > 0 && left == 0) {
    app.world.inventory.buildSelection = [];
    app.world.inventory.showBuildWindow = false;
  }

  igEnd();
  igPopFont();
}
