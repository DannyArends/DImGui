/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import widgets : cSlider, setting, infoRow;

static const(float)[] speeds = [0, 1, 2, 4, 8, 16, 32, 64];
static immutable(char*)[] speedLabels = ["Pause".ptr, "1x".ptr, "2x".ptr, "4x".ptr, "8x".ptr, "16x".ptr, "32x".ptr, "64x".ptr];

/** Show the GUI window for the World */
void showWorldContent(ref GameApp app, uint font = 0) {
  igBeginTable("World_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
  cSlider("Time Scale", app.timeScale, speeds, speedLabels, 150, app.gui.uiscale);
  setting("World Seed", app.world.seed[0], 0, 1000, 150, app.gui.uiscale);
  setting("Tile Seed", app.world.seed[1], 0, 1000, 150, app.gui.uiscale);
  setting("Render Distance", app.world.renderDistance, 1, 16, 150, app.gui.uiscale);
  setting("Tile Size", app.world.tileSize, 0.1f, 5.0f, 150, app.gui.uiscale);
  setting("Tile Height", app.world.tileHeight, 0.05f, 2.0f, 150, app.gui.uiscale);
  setting("Chunk Size", app.world.chunkSize, 4, 32, 150, app.gui.uiscale);
  setting("Chunk Height", app.world.chunkHeight, 2, 32, 150, app.gui.uiscale);
  infoRow("Chunks loaded", "%d", app.world.chunks.length);
  igEndTable();

  if(igButton("Regenerate", ImVec2(0.0f, 0.0f))) { app.world.deleteWorld(app); }
}

