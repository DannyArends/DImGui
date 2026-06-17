/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import game;

import imgui : iconText;
import stockpile : Stockpile, capacity, removeStockpile, slotsPerTile;
import widgets : text;

private enum GroupState { none, some, all }

private bool accepted(ref Stockpile sp, ResourceType t) {
  return sp.accepts.length == 0 || sp.accepts.get(t, false);
}

private void seed(ref Stockpile sp) {                 // materialize implicit accept-all before editing
  if(sp.accepts.length) return;
  foreach(a; [EnumMembers!ResourceType]) if(a != ResourceType.None) sp.accepts[a] = true;
}

private void acceptGroup(ref GameApp app, ref Stockpile sp, string label, bool wantBuildable) {
  // tally group state
  int total = 0, on = 0;
  foreach(t; [EnumMembers!ResourceType])
    if(t != ResourceType.None && resourceData(t).buildable == wantBuildable) { total++; if(sp.accepted(t)) on++; }
  auto gs = (on == 0) ? GroupState.none : (on == total) ? GroupState.all : GroupState.some;

  ImVec4 col = (gs == GroupState.all) ? ImVec4(0.3f,0.8f,0.3f,1) : (gs == GroupState.none) ? ImVec4(0.85f,0.3f,0.3f,1) : ImVec4(0.9f,0.8f,0.2f,1);

  // clickable colored header: click sets all on (unless already all -> all off)
  igPushStyleColor_Vec4(ImGuiCol_Text, col);
  bool open = igTreeNodeEx_Str(cstr("%s##grp%d", label, wantBuildable ? 1 : 0), ImGuiTreeNodeFlags_OpenOnArrow);
  igPopStyleColor(1);
  if(igIsItemClicked(0) && !igIsItemToggledOpen()) {
    sp.seed();
    bool target = (gs != GroupState.all);            // green->all off, otherwise all on
    foreach(t; [EnumMembers!ResourceType])
      if(t != ResourceType.None && resourceData(t).buildable == wantBuildable) sp.accepts[t] = target;
  }
  if(!open) return;

  // per-type: colored clickable label, no checkbox
  foreach(t; [EnumMembers!ResourceType]) {
    if(t == ResourceType.None || resourceData(t).buildable != wantBuildable) continue;
    bool a = sp.accepted(t);
    igPushStyleColor_Vec4(ImGuiCol_Text, a ? ImVec4(0.3f,0.8f,0.3f,1) : ImVec4(0.85f,0.3f,0.3f,1));
    if(igSelectable_Bool(cstr("%s##acc%d", resourceData(t).name, cast(int)t), false, 0, ImVec2(0,0))) {
      sp.seed();
      sp.accepts[t] = !a;
    }
    igPopStyleColor(1);
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