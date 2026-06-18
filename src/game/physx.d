/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import world : World;
import tile : surfaceAt, tileToWorld;

enum gravity = 2.5f;

/** Fall physics shared by blocks and dwarves: [y, v]; v != 0 while falling. */
struct Fall {
  float[2] state = [0.0f, 0.0f];                       /// [worldY, velocity]

  @property @nogc bool isFalling() const nothrow { return state[1] != 0.0f; }
  @property @nogc float y() const nothrow { return state[0]; }
  @property @nogc float v() const nothrow { return state[1]; }
  @property @nogc void y(float val) nothrow { state[0] = val; }
  @property @nogc void v(float val) nothrow { state[1] = val; }

  void start(ref World world, int[3] tile, float yOff = 0.0f) {
    if(isFalling) return;
    state = [world.tileToWorld(tile, yOff)[1], 0.001f];
  }

  bool step(ref World world, int[3] tile, float dt, float yOff, out int[3] landed) {
    v = v + gravity * dt;
    y = y - v * dt;
    int landTileY = world.surfaceAt(tile[0], tile[1] - 1, tile[2]);
    float landY = world.tileToWorld([tile[0], landTileY + 1, tile[2]], yOff)[1];
    if(y <= landY) { landed = [tile[0], landTileY + 1, tile[2]]; state = [landY, 0.0f]; return true; }
    return false;
  }
}
