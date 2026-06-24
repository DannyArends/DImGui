/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import matrix : translateScale;
import noise : noise2D;
import gameobjects : Clouds;

struct Cloud {
  float[3] origin;                          /// world-space corner (min X/Z), fixed Y
  float[3] drift = [0.4f, 0.0f, 0.15f];     /// units/sec
  uint seed;
  enum int W = 12, D = 12;                  /// cells in X, Z
}

/** Build/refresh the cloud instance buffer and advance drift. */
void cloudFrame(ref GameApp app, float dt) {
  if(app.world.clouds is null) return;
  float th = app.world.tileHeight;
  float cloudY = app.world.height + 8.0f * th;   // above the tallest terrain
  float ts = app.world.tileSize;

  DrawInstance[] inst;
  foreach(ref c; app.world.clouds.clouds) {
    c.origin[] += c.drift[] * dt;
    c.origin[1] = cloudY;
    foreach(z; 0 .. Cloud.D) foreach(x; 0 .. Cloud.W) {
      // blobby outline: threshold noise so it isn't a solid slab
      if(noise2D(cast(int)(c.origin[0]/ts) + x, cast(int)(c.origin[2]/ts) + z, c.seed) < 0.45f) continue;
      float[3] p = [c.origin[0] + x*ts, cloudY, c.origin[2] + z*ts];
      inst ~= DrawInstance([0,0], translateScale(p, [ts, th, ts]));
    }
  }
  app.world.clouds.instances = inst;
  app.world.clouds.instances.buffered = false;
}