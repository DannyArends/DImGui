/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import sfx : openAudio;

void checkSDLError() {
  const(char)* err = SDL_GetError();
  if (err[0] != '\0') { SDL_Log("SDL_GetError: '%s'", err); SDL_ClearError(); }
}

enum { MAIN = 0, TTF = 1, IMG = 2, MIX = 3 };
enum { START = 0, STARTUP = 1, FRAMESTART = 2, LASTTICK = 3 };

App initializeSDL() {
  int[4] init;
  App app;
  SDL_version linked;
  app.time[START] = SDL_GetTicks64();
  // Initialize Libraries
  init[MAIN] = SDL_Init(SDL_INIT_VIDEO);
  SDL_GetVersion(&linked);
  if(app.verbose) SDL_Log("SDL[C] v%u.%u.%u", SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_PATCHLEVEL);
  if(app.verbose) SDL_Log("SDL[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  init[TTF] = TTF_Init(); checkSDLError();
  linked = *TTF_Linked_Version();
  if(app.verbose) SDL_Log("TTF[C] v%u.%u.%u", SDL_TTF_MAJOR_VERSION, SDL_TTF_MINOR_VERSION, SDL_TTF_PATCHLEVEL);
  if(app.verbose) SDL_Log("TTF[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  init[IMG] = IMG_Init(IMG_INIT_JPG | IMG_INIT_PNG | IMG_INIT_TIF); checkSDLError();
  linked = *IMG_Linked_Version();
  if(app.verbose) SDL_Log("TTF[C] v%u.%u.%u", SDL_IMAGE_MAJOR_VERSION, SDL_IMAGE_MINOR_VERSION, SDL_IMAGE_PATCHLEVEL);
  if(app.verbose) SDL_Log("TTF[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  init[MIX] = Mix_Init(MIX_INIT_MP3 | MIX_INIT_OGG | MIX_INIT_MID); checkSDLError();
  linked = *Mix_Linked_Version();
  if(app.verbose) SDL_Log("MIX[C] v%u.%u.%u", SDL_MIXER_MAJOR_VERSION, SDL_MIXER_MINOR_VERSION, SDL_MIXER_PATCHLEVEL);
  if(app.verbose) SDL_Log("MIX[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  // Log all SDL library return codes
  if(app.verbose) SDL_Log("INIT: [%d,%d,%d,%d]", init[MAIN], init[TTF], init[IMG], init[MIX]);

  // Open Audio
  openAudio();

  // Create SDL Window
  SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
  app.window = SDL_CreateWindow(app.applicationName, SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), 1280, 720, window_flags);
  if(app.verbose) SDL_Log("SDL_CreateWindow: %p", app.window);
  return(app);
}

