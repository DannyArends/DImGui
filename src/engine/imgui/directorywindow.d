/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : dir, isdir, isfile, fsize;

ImVec2 textSize(const(char)* txt) {
  ImVec2 textSize; 
  igCalcTextSize(&textSize, txt, null, false, -1.0f);
  return(textSize);
}

void listDirContent(const(char)* path) {
  auto content = dir(path);
  foreach(elem; content) {
    auto ptr = toStringz(format("%s/%s", to!string(path), baseName(to!string(elem))));
    if(ptr.isdir) {
      auto flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_OpenOnDoubleClick;
      bool node_open = igTreeNodeEx_Str(ptr, flags);
      if (node_open) {
        listDirContent(ptr);
        igTreePop();
      }
    }else if(ptr.isfile) { // A file, just display as selectable text
      ImVec2 size;
      if(igSelectable_Bool(toStringz(baseName(to!string(elem))), false, 0, size)){ SDL_Log("Clicked: %s", ptr); }
      auto txt = toStringz(format("%.2fkb", fsize(ptr) / 1024.0f));
      igSameLine((igGetWindowWidth() - textSize(txt).x - 15.0f), 0);
      igText(txt);
    }
  }
}

void showDirectoryWindow(ref App app, bool* show, const(char)* path =  "data", uint font = 0){
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBegin("Directory", show, 0)) {
    listDirContent(path);
    igEnd();
  }else { igEnd(); }
  igPopFont();
}

