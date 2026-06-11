// DImGui - Cull shader
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

#include "scene.glsl"

layout(local_size_x = 64) in;

void main() {
  uint li = gl_GlobalInvocationID.x;
  if (li >= ubo.nlights) return;
  Light L = lightSSBO.lights[li];
  if (L.properties.w == 0.0) return;   // disabled
  if (L.position.w == 0.0) return;     // directional, handled as global light, not clustered

  vec3  cV = (ubo.view * vec4(L.position.xyz, 1.0)).xyz;   // center in view space
  float r  = L.cull.x;                                 // radius

  uvec3 lo, hi;                          // froxel index range the sphere covers

  float depth = -cV.z;                       // view-space distance (looks down -Z)
  float dmin = max(depth - r, 0.0001);
  float dmax = depth + r;

  // sphere entirely behind camera → skip
  if (dmax < 0.0001) return;

  // Z slices via the log mapping  slice = log2(d)*sliceScale + sliceBias
  int zlo = int(floor(log2(dmin) * ubo.clusterCfg.x + ubo.clusterCfg.y));
  int zhi = int(floor(log2(dmax) * ubo.clusterCfg.x + ubo.clusterCfg.y));

  // X/Y: conservative screen-space AABB of the view-space sphere via proj
  // project (cV ± r) extents; clip-space → NDC → screen tiles
  vec4 pc = ubo.proj * vec4(cV, 1.0);
  // TODO: conservative radius projection — over-includes froxels for near lights,
  // inflating cull cost and ClusterLights usage. Replace with proper view-space
  // sphere → screen-AABB (tangent-plane) projection. Suspected movement-hiccup cause.
  vec4 pr = ubo.proj * vec4(r, r, cV.z, 1.0);

  // screen-space center & half-extent in pixels
  vec2 ndc = pc.xy / max(pc.w, 0.0001);
  vec2 scr = (ndc * 0.5 + 0.5) * ubo.clusterCfg.zw;
  vec2 hpx = abs(pr.xy / max(pc.w, 0.0001)) * 0.5 * ubo.clusterCfg.zw;

  vec2 tile = ubo.clusterCfg.zw / vec2(ubo.grid.xy);
  int xlo = int(floor((scr.x - hpx.x) / tile.x));
  int xhi = int(floor((scr.x + hpx.x) / tile.x));
  int ylo = int(floor((scr.y - hpx.y) / tile.y));
  int yhi = int(floor((scr.y + hpx.y) / tile.y));

  // reject lights whose froxel range is entirely outside the grid (before clamping)
  if (zhi < 0 || zlo > int(ubo.grid.z)-1) return;
  if (xhi < 0 || xlo > int(ubo.grid.x)-1) return;
  if (yhi < 0 || ylo > int(ubo.grid.y)-1) return;

  lo = uvec3(clamp(xlo, 0, int(ubo.grid.x)-1), clamp(ylo, 0, int(ubo.grid.y)-1), clamp(zlo, 0, int(ubo.grid.z)-1));
  hi = uvec3(clamp(xhi, 0, int(ubo.grid.x)-1), clamp(yhi, 0, int(ubo.grid.y)-1), clamp(zhi, 0, int(ubo.grid.z)-1));

  for (uint z = lo.z; z <= hi.z; ++z) { for (uint y = lo.y; y <= hi.y; ++y) { for (uint x = lo.x; x <= hi.x; ++x) {
    uint cid = (z * ubo.grid.y + y) * ubo.grid.x + x;
    uint n = atomicAdd(cursor[0].cursor, 1u);
    if (n >= ubo.indexBufferLength) continue;             // drop-for-now; cursor still counts → grow-ready
    indices[n].light = li;
    indices[n].next = atomicExchange(head[cid].head, n);
  } } }
}

