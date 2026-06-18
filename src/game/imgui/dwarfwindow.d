/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import dwarf : spawnDwarf;
import jobs : dispatchJob, jobQueue, dropBlockJob;
import imgui : faIcon, iconText;
import tile : tileToWorld;
import textures : ImTextureRefFromID, idx;
import widgets : drawCenteredText, text;

/** Tile icon */
void showTileIcons(ref GameApp app, ResourceType[] tiles, float cellSize = 16.0f) {
  foreach(tt; tiles.sort.uniq) {
    igSameLine(0, 2);
    auto name = resourceData(tt).name;
    auto texIdx = idx(app.textures, name ~ "_base");
    if(texIdx < 0) continue;
    auto texID = ImTextureRefFromID(cast(ulong)app.textures[texIdx].imID);
    igImage(texID, ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1));
    if(igIsItemHovered(0)) { igSetTooltip(cstr("%s x%d", name, tiles.count(tt))); }
  }
}

/** Human-readable state label */
string dwarfStatus(ref Dwarf d) {
  switch(d.state) {
    case DwarfState.Wandering: return "Wandering";
    case DwarfState.WaitingForPath: return d.jobStack.length > 0 ? format("Pathing -> %s", d.jobStack[0].name) : "Pathing";
    case DwarfState.Moving: return d.jobStack.length > 0 ? format("Walking -> %s", d.jobStack[0].name) : "Walking";
    case DwarfState.Working: return d.jobStack.length > 0 ? format("%s%s", d.jobStack[0].name, d.jobStack[0].state) : "Working";
    case DwarfState.Blocked: return "Blocked";
    default: return "Idle";
  }
}

/** Coloured user glyph */
void dwarfGlyph(ref Dwarf d) {
  igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(d.color[0], d.color[1], d.color[2], d.color[3]));
  text("%s", fromStringz(faIcon(cast(string)ICON_FA_USER)));
  igPopStyleColor(1);
}

/** One clickable overview row: [glyph] name | tile - status | icons — all one line */
void showDwarfRow(ref GameApp app, size_t i, ref Dwarf d) {
  dwarfGlyph(d);
  igSameLine(0, 5);

  ImVec2 sz; igCalcTextSize(&sz, cstr("%s", d.name), null, false, -1.0f);
  bool isSel = app.world.dwarves.selected == cast(int)i;
  if(igSelectable_Bool(cstr("%s##dwf%d", d.name, i), isSel, 0, ImVec2(sz.x, 0))) { app.world.dwarves.selected = cast(int)i; }

  igSameLine(0, 5);
  text("%s - %s", d.tile, dwarfStatus(d));
  if(d.hasJob) {
    auto j = d.currentJob;
    text("    -> %s tgt=%s blk=%s reach=%d", j.name, j.targetTile, j.blockIDs.length ? format("%d", j.blockIDs[0]) : "-", cast(int)j.reach);
  }
}

/** One inventory slot cell: empty placeholder, or item icon with count + click-to-drop */
void showInventorySlot(ref GameApp app, ref Dwarf d, size_t i, float cellSize) {
  auto s = &d.inventory[i];
  if(s.empty) {
    igImageButton(cstr("##dwf_inv_%d", cast(int)i), ImTextureRefFromID(0), ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1), ImVec4(0,0,0,0), ImVec4(0,0,0,0));
    return;
  }
  auto texName = resourceData(s.type).buildable ? resourceData(s.type).name ~ "_base" : resourceData(s.type).name;
  auto texIdx  = idx(app.textures, texName);
  auto texID   = ImTextureRefFromID(cast(ulong)(texIdx >= 0 ? app.textures[texIdx].imID : null));
  igImageButton(cstr("##dwf_inv_%d", cast(int)i), texID, ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1), ImVec4(0,0,0,0), ImVec4(1,1,1,1));
  if(igIsItemClicked(0)) app.dispatchJob(d, dropBlockJob(d.tile, s.resourceIDs[s.count - 1]));
  ImVec2 pos, posMax; igGetItemRectMin(&pos); igGetItemRectMax(&posMax);
  if(s.count > 1) drawCenteredText(igGetWindowDrawList(), pos, posMax, cstr("%d", s.count));
  if(igIsItemHovered(0)) igSetTooltip(cstr("%s x%d (click to drop)", resourceData(s.type).name, s.count));
}

/** Detailed sheet for the selected dwarf */
void followDwarf(ref GameApp app, uint uid) {
  app.camera.onFrame = (dt) {
    foreach(ref dw; app.world.dwarves.dwarves){ if(dw.uid == uid) { app.camera.lookat = dw.visualPos; app.camera.isDirty = true; return; } }
    app.camera.onFrame = null;
  };
}

/** Detailed sheet for the selected dwarf */
void showDwarfSheet(ref GameApp app, ref Dwarf d, int selected) {
  dwarfGlyph(d); igSameLine(0, 5);
  if(igSelectable_Bool(cstr("%s##follow", d.name), false, 0, ImVec2(0, 0))) { app.followDwarf(d.uid); }
  text("Tile: %s", d.tile);
  text("Hunger: %.0f", d.hunger * 100.0f);
  text("Job: %s", d.hasJob ? d.currentJob.name : "Idle");
  igSeparator();
  igText("Inventory:");
  float cellSize = 32.0f;
  int cols = cast(int)floor((app.gui.panelW - cellSize) / cast(float)(cellSize + 4)) - 1;
  if(cols < 1) cols = 1;
  int col = 0;
  foreach(i, ref s; d.inventory) {
    app.showInventorySlot(d, i, cellSize);
    if(++col < cols) igSameLine(0, 4); else col = 0;
  }
}

/** Roster of all dwarves + queue summary */
void showDwarfOverview(ref GameApp app) {
  int idle, walking, working;
  if(app.world.dwarves !is null) { foreach(i, ref d; app.world.dwarves.dwarves) {
    switch(d.state) {
      case DwarfState.Idle: idle++; break;
      case DwarfState.Moving: walking++; break;
      case DwarfState.Working: working++; break;
      default: break;
    }
    app.showDwarfRow(i, d);
  } }
  text("Queue: %d | Idle: %d | Walking: %d | Working: %d", jobQueue.length, idle, walking, working);
}

void showDwarfContent(ref GameApp app, uint font = 0) {
  igText("Spawn Dwarf:"); igSameLine(0, 5);
  if(igButton(iconText(cast(string)ICON_FA_PLUS, "Spawn"), ImVec2(0,0))) { app.spawnDwarf(); }
  igSeparator();

  int sel = app.world.dwarves !is null ? app.world.dwarves.selected : -1;
  if(sel >= 0 && sel < app.world.dwarves.dwarves.length) {
    if(igButton(iconText(cast(string)ICON_FA_ARROW_LEFT, "Back"), ImVec2(0,0))) { app.world.dwarves.selected = -1; }
    app.showDwarfSheet(app.world.dwarves.dwarves[sel], sel);
  } else { app.showDwarfOverview(); }
  igNewLine();
  igSeparator();
  foreach(ref j; jobQueue) text("  [%s] -> %s (%s)", j.name, j.targetTile, j.tileType);
}
