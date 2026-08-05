/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import lattice : tileToWorld;
import vector : y;

enum gravity = 2.5f;

/** Fall physics: [y, v]; v != 0 while falling. */
struct Fall {
  float[2] state = [0.0f, 0.0f];      /// [worldY, velocity]
  float weight = 1.0f;                /// gravity multiplier (heavier = faster)
  float landY = 0.0f;                 /// world-Y to stop at (cached at start)
  int[3] landedTile;                  /// tile to occupy on landing (cached at start)

  @property @nogc bool isFalling() const nothrow { return state[1] != 0.0f; }
  @property @nogc float y() const nothrow { return state[0]; }
  @property @nogc float v() const nothrow { return state[1]; }
  @property @nogc void y(float val) nothrow { state[0] = val; }
  @property @nogc void v(float val) nothrow { state[1] = val; }

  @nogc void start(T)(const T lattice, int[3] from, int[3] to, float yOff = 0.0f) nothrow {
    if(isFalling) return;
    landedTile = to;
    landY = lattice.tileToWorld(to, yOff).y;
    state = [lattice.tileToWorld(from, yOff).y, 0.001f];
  }

  @nogc bool step(float dt) nothrow {
    v = v + gravity * weight * dt;
    y = y - v * dt;
    if(y <= landY) { state = [landY, 0.0f]; return true; }
    return false;
  }
}
