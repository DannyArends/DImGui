/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : iconText;
import widgets : textSize;
import io : dir, isdir, isfile, fsize;

void listDirContent(ref App app, const(char)* path) {
  auto content = dir(path);
  foreach(elem; content) {
    auto file = format("%s/%s", to!string(path), baseName(to!string(elem)));
    auto ptr = toStringz(file);
    if(ptr.isdir) {
      auto flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_OpenOnDoubleClick;
      bool node_open = igTreeNodeEx_Str(iconText(cast(string)ICON_FA_FOLDER, baseName(to!string(elem))), flags);
      if (node_open) {
        app.listDirContent(ptr);
        igTreePop();
      }
    } else if(ptr.isfile) {
      ImVec2 size;
      if(igSelectable_Bool(iconText(cast(string)ICON_FA_FILE, baseName(to!string(elem))), false, 0, size)) { 
        SDL_Log("Clicked: %s", ptr);
        app.concurrency.paths ~= file;
      }
      auto txt = toStringz(format("%.2fkb", fsize(ptr) / 1024.0f));
      igSameLine((igGetWindowWidth() - textSize(txt).x - 25.0f), 0);
      igText(txt);
    }
  }
}

void showDirectoryContent(ref App app, uint font = 0) { app.listDirContent("data"); }
