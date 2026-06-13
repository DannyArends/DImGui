// DImGui - Cull shader
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

#include "scene.glsl"
#include "functions.glsl"

layout(local_size_x = 64) in;

void main() {
  uint li = gl_GlobalInvocationID.x;
  if (li >= ubo.nlights) return;
  Light L = lightSSBO.lights[li];
  if (L.properties.w == 0.0) return;   // disabled
  if (L.position.w == 0.0) return;     // directional, handled as global light, not clustered

  vec3 cV = (ubo.view * vec4(L.position.xyz, 1.0)).xyz;   // center in view space
  float r  = L.cull.x; // radius
  float depth = -cV.z; // view-space distance (looks down -Z)
  float dmax = depth + r;

  // sphere entirely behind camera, skip it
  if (dmax < 0.0001) return;

  // Z slices via the log mapping  slice = log2(d)*sliceScale + sliceBias
  int zlo = int(floor(log2(max(depth - r, 0.0001)) * ubo.clusterCfg.x + ubo.clusterCfg.y));
  int zhi = int(floor(log2(dmax) * ubo.clusterCfg.x + ubo.clusterCfg.y));

  vec2 nx, ny;
  if (depth <= r) {
    nx = vec2(-1.0, 1.0); 
    ny = vec2(-1.0, 1.0);
  } else {
    nx = projectAxis(cV.x, cV.z, r, ubo.proj[0][0], depth);
    ny = projectAxis(cV.y, cV.z, r, ubo.proj[1][1], depth);
  }

  // NDC [-1,1] → screen tiles
  vec2 tile = ubo.clusterCfg.zw / vec2(ubo.grid.xy);
  int xlo = int(floor((nx.x * 0.5 + 0.5) * ubo.clusterCfg.z / tile.x));
  int xhi = int(floor((nx.y * 0.5 + 0.5) * ubo.clusterCfg.z / tile.x));
  int ylo = int(floor((ny.x * 0.5 + 0.5) * ubo.clusterCfg.w / tile.y));
  int yhi = int(floor((ny.y * 0.5 + 0.5) * ubo.clusterCfg.w / tile.y));

  // reject lights whose froxel range is entirely outside the grid (before clamping)
  if (zhi < 0 || zlo > int(ubo.grid.z)-1) return;
  if (xhi < 0 || xlo > int(ubo.grid.x)-1) return;
  if (yhi < 0 || ylo > int(ubo.grid.y)-1) return;

  // froxel index range the sphere covers
  uvec3 lo = uvec3(clamp(xlo, 0, int(ubo.grid.x)-1), clamp(ylo, 0, int(ubo.grid.y)-1), clamp(zlo, 0, int(ubo.grid.z)-1));
  uvec3 hi = uvec3(clamp(xhi, 0, int(ubo.grid.x)-1), clamp(yhi, 0, int(ubo.grid.y)-1), clamp(zhi, 0, int(ubo.grid.z)-1));

  for (uint z = lo.z; z <= hi.z; ++z) { for (uint y = lo.y; y <= hi.y; ++y) {
    uint rowBase = clusterId(0u, y, z);   // canonical layout; per-row hoist preserved
    for (uint x = lo.x; x <= hi.x; ++x) {
      uint n = atomicAdd(cursor[0].cursor, 1u);
      if (n >= ubo.indexBufferLength) continue;
      indices[n].light = li;
      indices[n].next = atomicExchange(head[rowBase + x].head, n);
    }
  } }
}

