/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : iconText;
import directorywindow : showDirectoryContent;
import sfxwindow : showSFXContent;
import objectswindow : showObjectsContent;
import shaderswindow : showShaderContent;
import texturewindow : showTexturesContent;

/** Single docked side panel with collapsible sections; draggable (left edge) variable width. */
void showSidepanel(ref App app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);

  auto flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoBringToFrontOnFocus;
  float dispW = app.gui.io.DisplaySize.x, dispH = app.gui.io.DisplaySize.y;
  bool landscape = dispW > dispH;

  if(landscape) { // Right edge, drag the LEFT edge (variable width)
    float panelH = dispH - app.gui.menuH;
    igSetNextWindowPos(ImVec2(dispW - app.gui.panelW, app.gui.menuH), ImGuiCond_Always, ImVec2(0,0));
    igSetNextWindowSize(ImVec2(app.gui.panelW, panelH), ImGuiCond_FirstUseEver);
    igSetNextWindowSizeConstraints(ImVec2(150, panelH), ImVec2(dispW * 0.8f, panelH), null, null);
  } else { // Bottom edge, drag the TOP edge (variable height)
    igSetNextWindowPos(ImVec2(0, dispH - app.gui.panelH), ImGuiCond_Always, ImVec2(0,0));
    igSetNextWindowSize(ImVec2(dispW, app.gui.panelH), ImGuiCond_FirstUseEver);
    igSetNextWindowSizeConstraints(ImVec2(dispW, 120), ImVec2(dispW, dispH - app.gui.menuH), null, null);
  }

  igBegin("##sidepanel", null, flags);

  ImVec2 sz; igGetWindowSize(&sz);
  if(landscape) { app.gui.panelW = sz.x; }else{ app.gui.panelH = sz.y; }

  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_FOLDER, "Load"), 0)) app.showDirectoryContent(font);
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_CUBES, "Objects"), 0)) app.showObjectsContent(font);
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_VOLUME_HIGH, "Sounds"), 0)) app.showSFXContent(font);
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_IMAGE, "Textures"), 0)) app.showTexturesContent(font);
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_CODE, "Shaders"), 0)) app.showShaderContent(font);
  foreach(window; app.gameWindows) {
    if(window.floating || window.direct) continue;
    if(igCollapsingHeader_TreeNodeFlags(toStringz(window.label), 0)) window.show(font);
  }
  igEnd();
  igPopFont();
}
