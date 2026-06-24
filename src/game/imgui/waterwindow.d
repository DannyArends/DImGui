/**
 * Authors: Danny Arends
 * License: GPL-v3
 */
 
import game;

import widgets : infoRow, text;
import tile : getWater, tileBelow, tileAbove, getTileAt;

/** Read-only water info for the tile currently under the cursor. */
void showWaterContent(ref GameApp app, uint font = 0) {
  int total = 0, cells = 0;
  foreach(coord; app.world.chunks.keys) {
    foreach(v; app.world.chunks[coord].waterLevel) if(v > 0) { total += v; cells++; }
  }
  if(igBeginTable("Water_Tbl", 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    infoRow("Wet cells",   "%d", cells);
    infoRow("Total water", "%d", total);
    int[3] t = app.world.inventory.tile;
    infoRow("Cursor tile", "%d,%d,%d", t[0], t[1], t[2]);
    infoRow("Water @cursor","%d", t == noTile ? 0 : app.getWater(t));
    igEndTable();
  }
}