/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

auto timed(alias fn, T, Args...)(ref T app, Args args) {
  debug { if(app.trace) {
    ulong t0 = SDL_GetTicks();
    scope(exit) {
      ulong dt = SDL_GetTicks() - t0;
      if(dt > 3) SDL_Log("SLOW %s=%dms", __traits(identifier, fn).ptr, dt);
    }
  } }
  return fn(app, args);
}

