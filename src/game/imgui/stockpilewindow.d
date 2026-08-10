/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import game;

import std.string : stripRight;

import imgui : iconText;
import stockpile : Stockpile, capacity, removeStockpile, countOf;
import widgets : text, cTag, cNode;

private Item matKey(ResourceType t) { return Item(ItemTemplate.None, t); }
private bool has(ref Stockpile sp, Item key) { return sp.accepts.length == 0 || sp.accepts.get(key, false); }
private bool ok(ref Stockpile sp, ResourceType t) { return sp.has(matKey(t)); }
private bool ok(ref Stockpile sp, ItemTemplate t) { return sp.has(craftKey(t)); }
private void seed(ref Stockpile sp) {
  if(sp.accepts.length) return;
  foreach(t; typesWhere(t => true)) sp.accepts[matKey(t)] = true;
  foreach(ti; 1 .. cast(int)ItemTemplate.max + 1) sp.accepts[Item(cast(ItemTemplate)ti)] = true;
}
private string base(ResourceType t) { return resourceTable[t].name.stripRight("0123456789_"); }
private Colors tri(int on, int total) { return on == 0 ? Colors.firebrick : on == total ? Colors.green : Colors.yellow; }
private auto typesWhere(scope bool delegate(ResourceType) keep) { return [EnumMembers!ResourceType].filter!(t => t != ResourceType.None && keep(t)); }
private Item craftKey(ItemTemplate t) { return Item(t); }

/** Leaf label: "Name  (n)##id", count shown only when stocked. */
private const(char)* leaf(const Stockpile sp, const Drops drops, ResourceType t, string label) {
  uint n = sp.countOf(drops, matKey(t));
  return n > 0 ? cstr("%s  (%d)##%d", label, n, cast(int)t) : cstr("%s##%d", label, cast(int)t);
}

/** Walk types matching `keep`, set them all to `on`. */
private void setAll(ref Stockpile sp, bool delegate(ResourceType) keep, bool on) { sp.seed(); foreach(t; typesWhere(keep)){ sp.accepts[matKey(t)] = on; } }
private void setAll(ref Stockpile sp, bool on) { sp.seed(); foreach(ti; 1 .. cast(int)ItemTemplate.max + 1) sp.accepts[craftKey(cast(ItemTemplate)ti)] = on; }
private void tally(ref Stockpile sp, bool delegate(ResourceType) keep, out int total, out int on) { foreach(t; typesWhere(keep)) { total++; if(sp.ok(t)) on++; } }

private void acceptGroup(ref GameApp app, ref Stockpile sp, string label, bool buildable) {
  bool inGroup(ResourceType t) { return t.buildable == buildable; }
  int gT, gOn; sp.tally(t => inGroup(t), gT, gOn);
  if(gT == 0) return;

  if(!cNode(cstr("%s##g%d", label, buildable), tri(gOn, gT), () => sp.setAll(t => inGroup(t), gOn != gT))) return;

  string[] bases;
  foreach(t; typesWhere(t => inGroup(t))) if(!bases.canFind(base(t))) bases ~= base(t);

  foreach(b; bases) {
    bool inBase(ResourceType t) { return inGroup(t) && base(t) == b; }
    int bT, bOn; sp.tally(t => inBase(t), bT, bOn);
    igPushID_Str(b.toStringz);
    if(bT == 1) {                                            // single variant -> base name as leaf
      foreach(t; typesWhere(t => inBase(t))) {
        if(cTag(sp.leaf(app.world.drops, t, b), sp.ok(t) ? Colors.green : Colors.firebrick)) { sp.seed(); sp.accepts[matKey(t)] = !sp.ok(t); } 
      }
    } else if(cNode(cstr("%s##b", b), tri(bOn, bT), () => sp.setAll(t => inBase(t), bOn != bT))) {
      foreach(t; typesWhere(t => inBase(t))) {
        if(cTag(sp.leaf(app.world.drops, t, resourceTable[t].name), sp.ok(t) ? Colors.green : Colors.firebrick)) { sp.seed(); sp.accepts[matKey(t)] = !sp.ok(t); }
      }
      igTreePop();
    }
    igPopID();
  }
  igTreePop();
}

private void acceptCraftGroup(ref GameApp app, ref Stockpile sp) {
  int gT, gOn;
  foreach(ti; 1 .. cast(int)ItemTemplate.max + 1) { gT++; if(sp.ok(cast(ItemTemplate)ti)) gOn++; }
  if(gT == 0) return;

  if(!cNode(cstr("Crafts##gc"), tri(gOn, gT), () => sp.setAll(gOn != gT))) return;
  foreach(ti; 1 .. cast(int)ItemTemplate.max + 1) {
    auto t = cast(ItemTemplate)ti;
    uint n = sp.countOf(app.world.drops, craftKey(t));
    auto lbl = n > 0 ? cstr("%s  (%d)##c%d", itemTemplateTable[t].name, n, ti) : cstr("%s##c%d", itemTemplateTable[t].name, ti);
    if(cTag(lbl, sp.ok(t) ? Colors.green : Colors.firebrick)) { sp.seed(); sp.accepts[craftKey(t)] = !sp.ok(t); }
  }
  igTreePop();
}

void showStockpileContent(ref GameApp app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(!app.world.stockpiles.length) text("No stockpiles");

  uint[] toDelete;
  foreach(id, ref sp; app.world.stockpiles) {
    igPushID_Int(cast(int)id);
    igSeparator();
    text("%s   %d / %d", sp.name, cast(int)sp.contents.length, cast(int)sp.capacity);
    app.acceptGroup(sp, "Blocks", true);
    app.acceptGroup(sp, "Items", false);
    app.acceptCraftGroup(sp);
    if(igButton(iconText(cast(string)ICON_FA_TRASH, "Delete"), ImVec2(0,0))) toDelete ~= id;
    igPopID();
  }
  foreach(id; toDelete){ app.world.removeStockpile(id); }
  igPopFont();
}
