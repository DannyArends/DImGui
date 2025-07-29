/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import textures : ImTextureRefFromID;

/** Show the GUI window which shows loaded Textures
 */
void showTextureswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBegin("Textures", show, 0)){
    igBeginTable("Texture_Tbl", 3,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, texture; app.textures) {
      if(fromStringz(texture.path) == "empty") continue;
      float ratio = cast(float)(texture.height) / texture.width;
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(toStringz(baseName(fromStringz(texture.path))), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igText("%d x %d", texture.width, texture.height);
      igTableNextColumn();
      igImage(ImTextureRefFromID(cast(ulong)texture.imID), ImVec2(100, min(100, cast(uint)(100 * ratio))), ImVec2(0, 0), ImVec2(1, 1));
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

