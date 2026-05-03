/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import dwarf : spawnDwarf, DwarfState, randomDwarfName;
import jobs : jobQueue;
import imgui : faIcon, iconText;
import textures : ImTextureRefFromID, idx;
import tileatlas : tileData;

void showTileIcons(ref App app, TileType[] tiles, float cellSize = 16.0f) {
  foreach(tt; tiles.sort.uniq) {
    igSameLine(0, 2);
    auto name = tileData[tt].name;
    auto texIdx = idx(app.textures, name ~ "_base");
    if(texIdx < 0) continue;
    auto texID = ImTextureRefFromID(cast(ulong)app.textures[texIdx].imID);
    igImage(texID, ImVec2(cellSize, cellSize), ImVec2(0,0), ImVec2(1,1));
    if(igIsItemHovered(0)) igSetTooltip(toStringz(format("%s x%d", name, tiles.count(tt))));
  }
}

void showDwarfContent(ref App app, uint font = 0) {
  igText("Spawn Dwarf:");
  igSameLine(0, 5);
  if(igButton(iconText(cast(string)ICON_FA_PLUS, "Spawn"), ImVec2(0,0))) { app.spawnDwarf(randomDwarfName()); }

  igSeparator();

  int idle = 0, walking = 0, working = 0;
  if(app.world.dwarves !is null) foreach(ref d; app.world.dwarves) {
    string status;
    if(d.state == DwarfState.Idle) { status = "Idle"; idle++; }
    else if(d.state == DwarfState.Wandering) { status = "Wandering"; }
    else if(d.state == DwarfState.WaitingForPath) { status = d.jobStack.length > 0 ? format("Pathing -> %s", d.jobStack[0].name) : "Pathing"; }
    else if(d.state == DwarfState.Moving) { status = d.jobStack.length > 0 ? format("Walking -> %s", d.jobStack[0].name) : "Walking"; walking++; }
    else if(d.state == DwarfState.Working) { status = d.jobStack.length > 0 ? d.jobStack[0].name : "Working"; working++; }
    else if(d.state == DwarfState.Blocked) { status = "Blocked"; }
    igText(toStringz("%s"), toStringz(format("%s %s", fromStringz(faIcon(cast(string)ICON_FA_USER)), d.name)));
    if(d.carrying.length > 0) {
      igSameLine(0, 5);
      TileType[] types;
      foreach(id; d.carrying) { foreach(ref b; app.world.blocks.blocks) { if(b.id == id) { types ~= b.type; break; } } }
      app.showTileIcons(types);
    }
    igText(toStringz("%s"), toStringz(format("%s - %s\n", d.tile, status)));
  }
  igText(toStringz(format("Queue: %d | Idle: %d | Walking: %d | Working: %d", jobQueue.length, idle, walking, working)));

  igSeparator();
  foreach(ref j; jobQueue) { igText(toStringz(format("  [%s] -> %s (%s)", j.name, j.targetTile, j.tileType))); }
}

