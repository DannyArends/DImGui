/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Main Menu
 */
void showMenu(ref App app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBeginMainMenuBar()) {
    version(Android) { igSetCursorPosX(60.0f * app.gui.uiscale); } // Nudge the start position on Android
    if(igBeginMenu("File".toStringz, true)) {
      if(igMenuItem_Bool("Load".toStringz,null, false, true)) {  app.gui.showDirectory = !app.gui.showDirectory; }
      if(igMenuItem_Bool("Demo".toStringz,null, false, true)) {  app.gui.showDemo = !app.gui.showDemo; }
      igEndMenu();
    }
    if(igBeginMenu("Edit".toStringz, true)) {
      if(igMenuItem_Bool("Objects".toStringz,null, false, true)) { app.gui.showObjects = !app.gui.showObjects; }
      if(igMenuItem_Bool("Textures".toStringz,null, false, true)) {  app.gui.showTexture = !app.gui.showTexture; }
      if(igMenuItem_Bool("Sounds".toStringz,null, false, true)) { app.gui.showSFX = !app.gui.showSFX; }
      igEndMenu();
    }
    foreach(ref window; app.gameWindows) {
      if(!window.floating && !window.direct) continue;
      if(igMenuItem_Bool(toStringz(window.label), null, window.visible, true)) window.visible = !window.visible;
    }
    if(igBeginMenu("?".toStringz, true)) {
      if(igMenuItem_Bool("Shaders".toStringz,null, false, true)) { app.gui.showShaders = !app.gui.showShaders; }
      igEndMenu();
    }
    igEndMainMenuBar();
  }
  igPopFont();
}
