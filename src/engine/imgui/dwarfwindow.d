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
  int claimed = 0;
  int mining  = 0;
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o;
    if(d is null) continue;
    if(d.targetTile[0] != int.min) {
      if(d.path.length == 0) mining++;
      else claimed++;
    }
  }
  igText(toStringz(format("Queue: %d jobs | Claimed: %d | Mining: %d", miningQueue.length, claimed, mining)));

  igSeparator();
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o;
    if(d is null) continue;
    igText(toStringz(format("%s %s @ [%d,%d,%d]", fromStringz(faIcon(cast(string)ICON_FA_USER)), d.dwarfName, d.tilePos[0], d.tilePos[1], d.tilePos[2])));
  }
}

