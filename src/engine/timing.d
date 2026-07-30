/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

enum MS_THRESHOLD = 3000;

auto timed(alias fn, T, Args...)(ref T app, Args args) {
  debug {
    ulong t0 = SDL_GetTicksNS();
    scope(exit) {
      ulong dt = app.timings[__traits(identifier, fn)] = (SDL_GetTicksNS() - t0) / 1000;
      if(app.trace && dt > MS_THRESHOLD) SDL_Log("SLOW %s=%dms", __traits(identifier, fn).ptr, dt);
    }
  }
  return fn(app, args);
}

