/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import game;

import imgui : iconText;     // or wherever dwarfwindow imports it from
import stockpile : Stockpile, capacity, removeStockpile, slotsPerTile;

void showStockpileContent(ref GameApp app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);

  if(app.world.stockpiles.length == 0) igText("No stockpiles. Use the warehouse tool to drag one out.".toStringz);

  uint[] toDelete;
  foreach(id, ref sp; app.world.stockpiles) {
    igPushID_Int(cast(int)id);
    igSeparator();
    igText(cstr("%s   %d / %d", sp.name, cast(int)sp.contents.length, cast(int)sp.capacity));

    // accept-type checkboxes; empty map = accept all
    foreach(t; [EnumMembers!ResourceType]) {
      if(t == ResourceType.None) continue;
      bool on = sp.accepts.length == 0 || sp.accepts.get(t, false);
      if(igCheckbox(cstr("%s##acc", resourceData(t).name), &on)) {
        if(sp.accepts.length == 0)                       // first edit: seed from "accept all"
          foreach(a; [EnumMembers!ResourceType]) if(a != ResourceType.None) sp.accepts[a] = true;
        sp.accepts[t] = on;
      }
    }

    if(igButton(iconText(cast(string)ICON_FA_TRASH, "Delete"), ImVec2(0,0))) toDelete ~= id;
    igPopID();
  }
  foreach(id; toDelete) app.removeStockpile(id);   // delete after iterating (don't mutate the map mid-loop)

  igPopFont();
}