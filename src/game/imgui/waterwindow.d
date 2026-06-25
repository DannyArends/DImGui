/**
 * Authors: Danny Arends
 * License: GPL-v3
 */
 
import game;

import widgets : infoRow, text;
import tile : getWater, tileBelow, tileAbove, getTileAt;

/** Read-only water stats + cursor inspection. */
void showWaterContent(ref GameApp app, uint font = 0) {
  int total = 0, cells = 0, active = 0, wetChunks = 0, visibleWetChunks = 0, dirtyChunks = 0;
  int instances = 0;
  ubyte maxLvl = 0;
  foreach(coord; app.world.chunks.keys) {
    auto chunk = app.world.chunks[coord];
    if(chunk.wetCells.length == 0) continue;
    wetChunks++;
    if(chunk.tiles.inFrustum) visibleWetChunks++;
    if(chunk.waterDirty) dirtyChunks++;
    instances += cast(int)chunk.waterInstances.length;
    cells += cast(int)chunk.wetCells.length;
    foreach(idx; chunk.wetCells) {
      ubyte l = chunk.waterLevel[idx];
      total += l;
      if(l > maxLvl) maxLvl = l;
    }
    active += cast(int)chunk.active.length;
  }
  int dormant = cells - active;
  float activePct = cells > 0 ? (100.0f * active / cells) : 0.0f;
  float avgDepth  = cells > 0 ? (cast(float)total / cells) : 0.0f;

  // raindrops in flight + the water they carry (settleRain deposits +4 each)
  int raindrops = 0;
  foreach(id, ref b; app.world.blocks) if(b.type == ResourceType.Water) raindrops++;
  int airWater = raindrops * 4;
  int totalWater = total + airWater;

  // cloud moisture (normalized 0..1 density summed across cells — separate unit)
  float cloudMoisture = 0;
  foreach(key, d; app.world.cloudDensity) cloudMoisture += d;

  if(igBeginTable("Water_Tbl", 2, ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    infoRow("Wet cells",     "%d", cells);
    infoRow("Active (sim)",  "%d", active);
    infoRow("Dormant",       "%d", dormant);
    infoRow("Active %",      "%.1f", activePct);
    infoRow("Wet chunks",    "%d", wetChunks);
    infoRow("Visible wet",   "%d", visibleWetChunks);
    infoRow("Dirty chunks",  "%d", dirtyChunks);
    infoRow("Render faces",  "%d", instances);
    infoRow("Ground water",  "%d", total);
    infoRow("Raindrops",     "%d", raindrops);
    infoRow("Air water",     "%d", airWater);
    infoRow("Total water",   "%d", totalWater);
    infoRow("Cloud moisture","%.1f", cloudMoisture);
    infoRow("Avg depth",     "%.2f", avgDepth);
    infoRow("Max depth",     "%d", cast(int)maxLvl);

    int[3] t = app.world.inventory.tile;
    infoRow("Cursor tile",   "%d,%d,%d", t[0], t[1], t[2]);
    infoRow("Water @cursor", "%d", t == noTile ? 0 : app.getWater(t));
    infoRow("Below @cursor", "%d", t == noTile ? 0 : app.getWater(t.tileBelow));
    igEndTable();
  }
}
