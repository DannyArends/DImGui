/**
 * Authors: Danny Arends
 * License: GPL-v3
 */
import game;

import widgets : infoRow;
import tile : getWater, setWater, tileBelow;
import water : waterTick;

/** Debug window: place/clear water at the cursor tile and step the sim manually */
void showWaterContent(ref GameApp app, uint font = 0) {
  int[3] t = app.world.inventory.tile;     // tile under the cursor ghost
  bool haveTile = (t != noTile);

  if(igBeginTable("Water_Tbl", 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    infoRow("Cursor tile", "%d,%d,%d", t[0], t[1], t[2]);
    infoRow("Water here",  "%d", haveTile ? app.getWater(t) : 0);
    infoRow("Below",       "%d", haveTile ? app.getWater(t.tileBelow) : 0);
    igEndTable();
  }

  if(igButton("Add 6 (full)", ImVec2(0,0)) && haveTile) app.setWater(t, 6);
  igSameLine(0, 6);
  if(igButton("Add 3", ImVec2(0,0)) && haveTile) app.setWater(t, 3);
  igSameLine(0, 6);
  if(igButton("Clear", ImVec2(0,0)) && haveTile) app.setWater(t, 0);

  if(igButton("Step sim x1", ImVec2(0,0))) app.waterTick();
  igSameLine(0, 6);
  if(igButton("Step sim x10", ImVec2(0,0))) foreach(_; 0..10) app.waterTick();
}