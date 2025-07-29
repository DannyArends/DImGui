/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import sfx : play;

/** Show the GUI window for Sound Effects
 */
void showSFXwindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBegin("Sounds", show, 0)){
    igSliderScalar("Volume", ImGuiDataType_Float,  &app.soundEffectGain, &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0); 
    igBeginTable("Sounds_Tbl", 2,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(i, sound; app.soundfx) {
      igPushID_Int(to!int(i));
      igTableNextRow(0, 5.0f);
      igTableNextColumn();
      igText(toStringz(baseName(fromStringz(sound.path))), ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      if(igButton("Play", ImVec2(0.0f, 0.0f))){ app.play(sound); }
      igPopID();
    }
    igEndTable();
    igEnd();
  }else { igEnd(); }
  igPopFont();
}
