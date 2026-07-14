/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : multiply, inverse;
import quaternion : xyzw;

enum SSAO_KERNEL = 32;
__gshared float[4][SSAO_KERNEL] ssaoKernel;

struct SSAOUniformBuffer {
  Matrix viewProj;                 // ori * proj * view
  Matrix invViewProj;              // inverse(ori * proj * view)
  float[4] camPos;                 // camera world position
  float[4][SSAO_KERNEL] kernel;
  float[4] params;                 // x=radius y=bias z=power w=enable
}

/** Hemisphere sample set (view space, +Z), clustered toward the origin. Built once. */
shared static this() {
  auto rng = Random(0xA0);   // deterministic
  foreach(i; 0 .. SSAO_KERNEL) {
    float[3] s = [uniform(-1.0f, 1.0f, rng), uniform(-1.0f, 1.0f, rng), uniform(0.0f, 1.0f, rng)];
    float len = sqrt(s[0]*s[0] + s[1]*s[1] + s[2]*s[2]);
    if(len > 0.0f) s[] /= len;
    float t = cast(float)i / SSAO_KERNEL;
    float scale = 0.1f + 0.9f * t * t;   // more samples near the origin
    ssaoKernel[i] = [s[0]*scale, s[1]*scale, s[2]*scale, 0.0f];
  }
}

void updateSSAO(ref App app, Descriptor d, uint syncIndex) {
  Matrix vp = app.camera.proj.multiply(app.camera.view);   // desktop: ori == identity, so this IS the depth transform
  SSAOUniformBuffer ubo = {
    viewProj: vp,
    invViewProj: vp.inverse,
    camPos: app.camera.position.xyzw,
    params: [1.0f, 0.05f, 1.5f, app.useSSAO ? 1.0f : 0.0f]
  };
  ubo.kernel = ssaoKernel;
  memcpy(app.ubos[d.base][syncIndex].data, &ubo, d.bytes);
}
