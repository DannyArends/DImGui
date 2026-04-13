/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Show the GUI window for the World
 */
void showWorldContent(ref App app, uint font = 0) {
  igBeginTable("World_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);

  int[2] seedLimits = [0, 1000];

  igTableNextColumn(); igText("World Seed", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igPushItemWidth(150 * app.gui.uiscale);
  igSliderScalar("##seed0", ImGuiDataType_S32, &app.world.seed[0], &seedLimits[0], &seedLimits[1], "%d", 0);

  igTableNextColumn(); igText("Tile Seed", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igPushItemWidth(150 * app.gui.uiscale);
  igSliderScalar("##seed1", ImGuiDataType_S32, &app.world.seed[1], &seedLimits[0], &seedLimits[1], "%d", 0);

  igTableNextColumn(); igText("Render Distance", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igPushItemWidth(150 * app.gui.uiscale);
  int[2] rdLimits = [1, 16];
  igSliderScalar("##rd", ImGuiDataType_S32, &app.world.renderDistance, &rdLimits[0], &rdLimits[1], "%d", 0);

  igTableNextColumn(); igText("Tile Size", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igPushItemWidth(150 * app.gui.uiscale);
  float[2] tsLimits = [0.1f, 5.0f];
  igSliderScalar("##ts", ImGuiDataType_Float, &app.world.tileSize, &tsLimits[0], &tsLimits[1], "%.2f", 0);

  igTableNextColumn(); igText("Tile Height", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igPushItemWidth(150 * app.gui.uiscale);
  float[2] thLimits = [0.05f, 2.0f];
  igSliderScalar("##th", ImGuiDataType_Float, &app.world.tileHeight, &thLimits[0], &thLimits[1], "%.2f", 0);

  igTableNextColumn(); igText("Chunk Size", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igPushItemWidth(150 * app.gui.uiscale);
  int[2] csLimits = [4, 32];
  igSliderScalar("##cs", ImGuiDataType_S32, &app.world.chunkSize, &csLimits[0], &csLimits[1], "%d", 0);

  igTableNextColumn(); igText("Chunk Height", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igPushItemWidth(150 * app.gui.uiscale);
  int[2] chLimits = [2, 32];
  igSliderScalar("##ch", ImGuiDataType_S32, &app.world.chunkHeight, &chLimits[0], &chLimits[1], "%d", 0);

  igTableNextColumn(); igText("Chunks loaded", ImVec2(0.0f, 0.0f)); igTableNextColumn();
  igText(toStringz(format("%d", app.world.chunks.length)), ImVec2(0.0f, 0.0f));
  igEndTable();

  if(igButton("Regenerate", ImVec2(0.0f, 0.0f))) { app.world.clear(app); }
}

