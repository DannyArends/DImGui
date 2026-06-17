/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import game;

import imgui : iconText;
import stockpile : Stockpile, capacity, removeStockpile, slotsPerTile;
import widgets : text;

private void acceptGroup(ref GameApp app, ref Stockpile sp, string label, bool wantBuildable) {
  if(!igTreeNode_Str(label.toStringz)) return;
  foreach(t; [EnumMembers!ResourceType]) {
    if(t == ResourceType.None || resourceData(t).buildable != wantBuildable) continue;
    bool on = sp.accepts.length == 0 || sp.accepts.get(t, false);
    if(igCheckbox(cstr("%s##acc%d", resourceData(t).name, cast(int)t), &on)) {
      if(sp.accepts.length == 0) { foreach(a; [EnumMembers!ResourceType]) if(a != ResourceType.None){ sp.accepts[a] = true; } }
      sp.accepts[t] = on;
    }
  }
  igTreePop();
}

void showStockpileContent(ref GameApp app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);

  if(app.world.stockpiles.length == 0){ text("No stockpiles"); }

  uint[] toDelete;
  foreach(id, ref sp; app.world.stockpiles) {
    igPushID_Int(cast(int)id);
    igSeparator();
    text("%s   %d / %d", sp.name, cast(int)sp.contents.length, cast(int)sp.capacity);

    app.acceptGroup(sp, "Blocks", true);
    app.acceptGroup(sp, "Items",  false);

    if(igButton(iconText(cast(string)ICON_FA_TRASH, "Delete"), ImVec2(0,0))) toDelete ~= id;
    igPopID();
  }
  foreach(id; toDelete) app.removeStockpile(id);

  igPopFont();
}