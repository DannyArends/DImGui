/**
 * Authors: Danny Arends
 * License: GPL-v3
 */
 
import game;

import widgets : infoRow, text;
import tile : getWater, tileBelow, tileAbove, getTileAt;

/** Read-only water stats + cursor inspection. */
void showWaterContent(ref GameApp app, uint font = 0) {
  int total = 0, cells = 0, active = 0, wetChunks = 0;
  ubyte maxLvl = 0;
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    if(chunk.wetCells.length == 0) continue;
    wetChunks++;
    cells += cast(int)chunk.wetCells.length;
    active += cast(int)chunk.activeCells.length;
    foreach(idx; chunk.wetCells) {
      ubyte l = chunk.waterLevel[idx];
      total += l;
      if(l > maxLvl) maxLvl = l;
    }
  }
  int dormant = cells - active;

  if(igBeginTable("Water_Tbl", 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    infoRow("Wet cells",    "%d", cells);
    infoRow("Active (sim)", "%d", active);
    infoRow("Dormant",      "%d", dormant);
    infoRow("Wet chunks",   "%d", wetChunks);
    infoRow("Total water",  "%d", total);
    infoRow("Max depth",    "%d", cast(int)maxLvl);

    int[3] t = app.world.inventory.tile;
    infoRow("Cursor tile",  "%d,%d,%d", t[0], t[1], t[2]);
    infoRow("Water @cursor","%d", t == noTile ? 0 : app.getWater(t));
    infoRow("Below @cursor","%d", t == noTile ? 0 : app.getWater(t.tileBelow));
    igEndTable();
  }
}
