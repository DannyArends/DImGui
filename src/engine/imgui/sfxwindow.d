/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import sfx : play;

/** Show the GUI window for Sound Effects
 */
void showSFXContent(ref App app, uint font = 0) {
  igSliderScalar("Volume", ImGuiDataType_Float, &app.soundEffectGain, &app.gui.sound[0], &app.gui.sound[1], "%.2f", 0);

  // Build names array for combo
  const(char)*[] names;
  foreach(sound; app.soundfx) names ~= toStringz(baseName(fromStringz(sound.path)));

  igCombo_Str_arr("##sound", &app.gui.selectedSound, names.ptr, cast(int)names.length, -1);
  igSameLine(0, 5);
  if(igButton("Play", ImVec2(0.0f, 0.0f))) app.play(app.soundfx[app.gui.selectedSound]);
}

