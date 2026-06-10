// DImGui - Cull shader
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

#include "scene.glsl"

layout(local_size_x = 64) in;

const uint NIL = 0xFFFFFFFFu;

void main() {
  uint li = gl_GlobalInvocationID.x;
  if (li >= nlights) return;
  Light L = lightSSBO.lights[li];
  if (L.properties.w == 0.0) return;   // disabled
  if (L.position.w == 0.0) return;     // directional → handled as global light, not clustered

  vec3  cV = (view * vec4(L.position.xyz, 1.0)).xyz;   // center in view space
  float r  = L.cull.x;                                  // radius

  uvec3 lo, hi;                          // froxel index range the sphere covers
  // (compute lo/hi — the one tricky block, detailed below)

  for (uint z = lo.z; z <= hi.z; ++z) { for (uint y = lo.y; y <= hi.y; ++y) { for (uint x = lo.x; x <= hi.x; ++x) {
    uint cid = (z * grid.y + y) * grid.x + x;
    uint n = atomicAdd(cursor[0].cursor, 1u);
    if (n >= indexBufferLength) return;             // drop-for-now; cursor still counts → grow-ready
    indices[n].light = li;
    indices[n].next  = atomicExchange(head[cid].head, n);
  } } }
}

