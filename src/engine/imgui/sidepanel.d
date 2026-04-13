/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : iconText;
import directorywindow : showDirectoryContent;
import settingswindow : showSettingsContent;
import sfxwindow : showSFXContent;
import objectswindow : showObjectsContent;
import lightswindow : showLightsContent;
import shaderswindow : showShaderContent;
import texturewindow : showTexturesContent;
import worldwindow : showWorldContent;

/** Single docked side panel with collapsible sections
 */
void showSidepanel(ref App app, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);

  auto flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize   | ImGuiWindowFlags_NoBringToFrontOnFocus;

  igSetNextWindowPos(ImVec2(app.gui.io.DisplaySize.x - app.gui.panelW, app.gui.menuH), ImGuiCond_Always, ImVec2(0,0));
  igSetNextWindowSize(ImVec2(app.gui.panelW, app.gui.io.DisplaySize.y - app.gui.menuH), ImGuiCond_Always);
  igBegin("##sidepanel", null, flags);

  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_FOLDER, "Load"), 0)) app.showDirectoryContent(font); 
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_CUBES, "Objects"), 0)) app.showObjectsContent(font); 
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_LIGHTBULB_O, "Lights"), 0)) app.showLightsContent(font); 
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_COG, "Settings"), 0)) app.showSettingsContent(font); 
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_GLOBE, "World"), 0)) app.showWorldContent(font); 
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_VOLUME_UP, "Sounds"), 0)) app.showSFXContent(font); 
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_PICTURE_O, "Textures"), 0)) app.showTexturesContent(font); 
  if(igCollapsingHeader_TreeNodeFlags(iconText(cast(string)ICON_FA_CODE, "Shaders"), 0)) app.showShaderContent(font); 
  igEnd();
  igPopFont();
}
