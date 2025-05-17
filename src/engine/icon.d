/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import includes;

import io : isfile;

/** Set an icon for the SDL window
 */
void setIcon(SDL_Window *window, const(char)* path = "assets/icons/icon.png") {
  if (path.isfile()) {
    SDL_Surface* surface = IMG_Load(path);
    SDL_SetWindowIcon(window, surface);
    SDL_FreeSurface(surface);
  }
}
