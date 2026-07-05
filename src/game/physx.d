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
  float weight = 1.0f;                                 /// gravity multiplier (heavier = faster)

  @property @nogc bool isFalling() const nothrow { return state[1] != 0.0f; }
  @property @nogc float y() const nothrow { return state[0]; }
  @property @nogc float v() const nothrow { return state[1]; }
  @property @nogc void y(float val) nothrow { state[0] = val; }
  @property @nogc void v(float val) nothrow { state[1] = val; }

  @nogc int[3] landingTile(const World world, int[3] tile) nothrow {
    int landTileY = world.surfaceAt(tile[0], tile[1] - 1, tile[2]);
    return [tile[0], landTileY + 1, tile[2]];
  }

  @nogc void start(const World world, int[3] tile, float yOff = 0.0f) nothrow {
    if(isFalling) return;
    state = [world.tileToWorld(tile, yOff)[1], 0.001f];
  }

  @nogc bool step(const World world, int[3] tile, float dt, float yOff, out int[3] landed) nothrow {
    v = v + gravity * weight * dt;
    y = y - v * dt;
    landed = landingTile(world, tile);
    float landY = world.tileToWorld(landed, yOff)[1];
    if(y <= landY) { state = [landY, 0.0f]; return true; }
    return false;
  }
}

/** True if `tile` is in the same column as `minedTile`, at or above it. */
@nogc bool inColumn(int[3] tile, int[3] minedTile) nothrow { 
  return(tile[0] == minedTile[0] && tile[2] == minedTile[2] && tile[1] >= minedTile[1]);
}
