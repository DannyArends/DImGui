/**
 * Authors: Danny Arends
 * License: GPL-v3
 */
 
import game;

import widgets : infoRow, text;
import tile : getWater, tileBelow, tileAbove, getTileAt;

/** Read-only water info for the tile currently under the cursor. */
void showWaterContent(ref GameApp app, uint font = 0) {
  int[3] t = app.world.inventory.tile;

  if(t == noTile) { text("Hover a tile to inspect water."); return; }

  if(igBeginTable("Water_Tbl", 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    infoRow("Tile",        "%d, %d, %d", t[0], t[1], t[2]);
    infoRow("Tile type",   "%s", resourceData(app.world.getTileAt(t)).name);
    infoRow("Water here",  "%d / 6", app.getWater(t));
    infoRow("Above",       "%d", app.getWater(t.tileAbove));
    infoRow("Below",       "%d", app.getWater(t.tileBelow));
    infoRow("Below type",  "%s", resourceData(app.world.getTileAt(t.tileBelow)).name);
    igEndTable();
  }
}