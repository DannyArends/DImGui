/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : fixPath, isfile;

/** Set an icon for the SDL window
 */
void setIcon(SDL_Window *window, const(char)* path = "data/icons/icon.png") {
  version(Android){ }else{
    if (path.isfile()) {
      path = fixPath(path);
      SDL_Surface* surface = IMG_Load(path);
      SDL_SetWindowIcon(window, surface);
      SDL_DestroySurface(surface);
      SDL_Log("Icon loaded from: %s", path);
    }
  }
}

