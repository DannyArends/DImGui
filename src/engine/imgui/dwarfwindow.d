/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import dwarf : spawnDwarf, randomDwarfName;
import jobs : jobQueue;
import imgui : faIcon, iconText;

void showDwarfContent(ref App app, uint font = 0) {
  igText("Spawn Dwarf:");
  igSameLine(0, 5);
  if(igButton(iconText(cast(string)ICON_FA_PLUS, "Spawn"), ImVec2(0,0))) { app.spawnDwarf(randomDwarfName()); }

  igSeparator();

  int idle = 0, walking = 0, working = 0;
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o;
    if(d is null) continue;
    string status;
    if(d.jobStack.length == 0) { status = "Idle"; idle++; }
    else if(d.path.length > 0) { status = format("Walking -> %s", d.jobStack[0].name); walking++; }
    else { status = d.jobStack[0].name; working++; }
    if(d.carrying.length > 0) status ~= format(" [carrying: %s]", d.carrying);
    igText(toStringz("%s"), toStringz(format("%s %s @ %s - %s", fromStringz(faIcon(cast(string)ICON_FA_USER)), d.name, d.tile, status)));
  }

  igSeparator();
  igText(toStringz(format("Queue: %d | Idle: %d | Walking: %d | Working: %d", jobQueue.length, idle, walking, working)));

  igSeparator();
  foreach(ref j; jobQueue) { igText(toStringz(format("  [%s] -> %s (%s)", j.name, j.targetTile, j.tileType))); }
}

