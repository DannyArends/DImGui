/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import dwarf : spawnDwarf, deleteDwarf;
import entitywindow : entityGlyph, followEntity, needToggle;
import imgui : iconText;
import jobs : jobQueue, dropBlockJob;
import lattice : tileToWorld;
import resources : itemName, itemTex;
import scheduler : dispatchJob;
import textures : ImTextureRefFromID, idx;
import widgets : drawCenteredText, text;

/** Human-readable state label */
string dwarfStatus(ref Dwarf d) {
  switch(d.state) {
    case EntityState.Wandering: return "Wandering";
    case EntityState.WaitingForPath: return d.jobStack.length > 0 ? format("Pathing -> %s", d.jobStack[0].name) : "Pathing";
    case EntityState.Moving: return d.jobStack.length > 0 ? format("Walking -> %s", d.jobStack[0].name) : "Walking";
    case EntityState.Working: return d.jobStack.length > 0 ? format("%s%s", d.jobStack[0].name, d.jobStack[0].state) : "Working";
    case EntityState.Blocked: return "Blocked";
    default: return "Idle";
  }
}

/** One clickable overview row: [glyph] name | tile - status | icons — all one line */
void showDwarfRow(ref GameApp app, size_t i, ref Dwarf d) {
  entityGlyph(d, cast(string)ICON_FA_USER);
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
  auto texIdx  = idx(app.textures, itemTex(s.item));
  auto texID = ImTextureRefFromID(cast(ulong)(texIdx >= 0 ? app.textures[texIdx].imID : null));
  igImageButton(cstr("##dwf_inv_%d", cast(int)i), texID, ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1), ImVec4(0,0,0,0), ImVec4(1,1,1,1));
  if(igIsItemClicked(0)) app.dispatchJob(d, dropBlockJob(d.tile, s.resourceIDs[s.count - 1]));
  ImVec2 pos, posMax; igGetItemRectMin(&pos); igGetItemRectMax(&posMax);
  if(s.count > 1) drawCenteredText(igGetWindowDrawList(), pos, posMax, cstr("%d", s.count));
  if(igIsItemHovered(0)) igSetTooltip(cstr("%s x%d (click to drop)", itemName(s.item), s.count));
}

/** Detailed sheet for the selected dwarf */
void showDwarfSheet(ref GameApp app, ref Dwarf d, int selected) {
  entityGlyph(d, cast(string)ICON_FA_USER); igSameLine(0, 5);
  if(igSelectable_Bool(cstr("%s##follow", d.name), false, 0, ImVec2(0, 0))) { app.followEntity(d.uid, app.world.dwarves); }
  if(igButton(iconText(cast(string)ICON_FA_TRASH, "Delete"), ImVec2(0, 0))) { app.deleteDwarf(selected); return; }
  text("Tile: %s", d.tile);
  needToggle("Hunger", "hungry", d.needs[Need.Hunger], "dwf_hunger");
  needToggle("Thirst", "thirsty", d.needs[Need.Thirst], "dwf_thirst");
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
      case EntityState.Idle: idle++; break;
      case EntityState.Moving: walking++; break;
      case EntityState.Working: working++; break;
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
  foreach(ref j; jobQueue) text("  [%s] -> %s (%s)", j.name, j.targetTile, j.tileClass);
}
