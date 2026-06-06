/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import dwarf : spawnDwarf;
import jobs : jobQueue;
import imgui : faIcon, iconText;
import textures : ImTextureRefFromID, idx;
import widgets : text, cstr;

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
}

/** Detailed sheet for the selected dwarf */
void showDwarfSheet(ref GameApp app, Dwarf* d) {
  dwarfGlyph(*d); igSameLine(0, 5);
  text("%s", d.name);
  text("Tile: %s", d.tile);
  text("Hunger: %.0f", d.hunger * 100.0f);
  text("Job: %s", d.jobStack.length > 0 ? d.jobStack[0].name : "Idle");
  igSeparator();
  igText("Inventory:");
  foreach(ref s; d.inventory) { if(!s.empty) { text("  %s x%d", resourceData(s.type).name, s.count); } }
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
    app.showDwarfSheet(&app.world.dwarves.dwarves[sel]);
  } else { app.showDwarfOverview(); }

  igSeparator();
  foreach(ref j; jobQueue) text("  [%s] -> %s (%s)", j.name, j.targetTile, j.tileType);
}
