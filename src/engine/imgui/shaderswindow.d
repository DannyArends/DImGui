/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Show the GUI window for Shaders
 */
void showShaderwindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
  if(igBegin("Shaders", show, 0)){
    igBeginTable("Shaders_Tbl", 3,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    auto shaders = (app.shadows.shaders ~ app.shaders ~ app.postProcess);
    if(app.hasCompute) shaders ~= app.compute.shaders;
    foreach(i, shader; shaders) {
      igPushID_Int(to!int(i));
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(toStringz(baseName(fromStringz(shader.path))), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igText(toStringz(format("%s", shader.stage)), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igText(toStringz(format("Descriptors: %s\nExecute as [%d, %d, %d]", shader.descriptors.length, shader.groupCount[0], shader.groupCount[1], shader.groupCount[2])), ImVec2(0.0f, 0.0f));
      igPopID();
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}
