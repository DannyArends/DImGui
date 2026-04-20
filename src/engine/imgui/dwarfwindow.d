/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import dwarf : Dwarf, miningQueue, spawnDwarf, randomDwarfName;
import imgui : faIcon, iconText;

void showDwarfContent(ref App app, uint font = 0) {
  igText("Spawn Dwarf:");
  igSameLine(0, 5);
  if(igButton(iconText(cast(string)ICON_FA_PLUS, "Spawn"), ImVec2(0,0))) { app.spawnDwarf(randomDwarfName()); }

  igSeparator();
  int walking = 0;
  int mining  = 0;
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o;
    if(d is null || d.targetTile[0] == int.min) continue;
    if(d.miningProgress > 0.0f) mining++;
    else walking++;
  }
  igText(toStringz(format("Queue: %d | Walking: %d | Mining: %d", miningQueue.length, walking, mining)));

  igSeparator();
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o;
    if(d is null) continue;
    string status;
    if(d.targetTile[0] == int.min) status = "Idle";
    else if(d.miningProgress > 0.0f) status = format("Mining %.0f", d.miningProgress * 100) ~ "%";
    else status = format("Walking (%d steps)", d.path.length);
    igText(toStringz("%s"), toStringz(format("%s %s @ %s - %s", fromStringz(faIcon(cast(string)ICON_FA_USER)), d.dwarfName, d.tilePos, status)));
  }
}

