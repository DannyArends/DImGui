/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import textures : ImTextureRefFromID;

/** Show the GUI window which shows loaded Textures
 */
void showTexturesContent(ref App app, uint font = 0) {
  const(char)*[] names;
  foreach(texture; app.textures) {
    if(fromStringz(texture.path) == "empty") continue;
    names ~= toStringz(baseName(fromStringz(texture.path)));
  }

  igCombo_Str_arr("##texture", &app.gui.selectedTexture, names.ptr, cast(int)names.length, -1);

  auto t = app.textures[app.gui.selectedTexture];
  float ratio = cast(float)(t.height) / t.width;
  igText("%d x %d", t.width, t.height);
  igImage(ImTextureRefFromID(cast(ulong)t.imID), ImVec2(app.gui.panelW - 20, min(app.gui.panelW - 20, (app.gui.panelW - 20) * ratio)), ImVec2(0, 0), ImVec2(1, 1));
}

