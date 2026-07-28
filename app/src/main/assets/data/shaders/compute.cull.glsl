// DImGui - Cull shader
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

#include "scene.glsl"
#include "functions.glsl"

layout(local_size_x = 64) in;

/** A light's bounding sphere in view space (cone lights use the cone's bounding sphere, not the full range sphere). */
struct BoundSphere { vec3 centre; float radius; };

/** Compute the view-space bounding sphere for a light: tight cone bound for spots, plain range sphere for points. */
BoundSphere lightBoundSphere(Light L) {
  vec3 centre = (ubo.view * vec4(L.position.xyz, 1.0)).xyz;   // apex (spot) or centre (point) in view space
  float range = L.cull.x;

  if (L.cull.z >= 0.9999) return BoundSphere(centre, range);   // point light: cull.z ~ 1, no cone

  float cosOuter = L.cull.z;
  vec3 axis = mat3(ubo.view) * L.direction.xyz; // cone axis, view space

  if (cosOuter >= 0.70710678) {                                // narrow cone (<=45deg): apex+base rim circumscribe
    float sphere = range * 0.5 / cosOuter;
    return BoundSphere(centre + axis * (sphere * cosOuter), sphere);
  }
  float baseRadius = range * sqrt(max(0.0, 1.0 - cosOuter * cosOuter));  // wide cone: base disc dominates
  return BoundSphere(centre + axis * (range * cosOuter), baseRadius);
}

/** Screen-space froxel index range [lo,hi] a view-space bounding sphere covers; returns false if fully off-grid. */
bool sphereFroxelRange(BoundSphere s, out uvec3 lo, out uvec3 hi) {
  float depth = -s.centre.z;                                  // view looks down -Z
  if (depth + s.radius < 0.0001) return false;                // entirely behind camera

  int zlo = int(floor(log2(max(depth - s.radius, 0.0001)) * ubo.clusterCfg.x + ubo.clusterCfg.y));
  int zhi = int(floor(log2(depth + s.radius) * ubo.clusterCfg.x + ubo.clusterCfg.y));

  vec2 nx, ny;
  if (depth <= s.radius) {                                    // camera inside sphere: spans full screen
    nx = vec2(-1.0, 1.0); ny = vec2(-1.0, 1.0); zlo = max(zlo, 0);
  } else {
    nx = projectAxis(s.centre.x, s.centre.z, s.radius, ubo.proj[0][0], depth);
    ny = projectAxis(s.centre.y, s.centre.z, s.radius, ubo.proj[1][1], depth);
  }

  int xlo = int(floor((nx.x * 0.5 + 0.5) * GRID_X)), xhi = int(floor((nx.y * 0.5 + 0.5) * GRID_X));
  int ylo = int(floor((ny.x * 0.5 + 0.5) * GRID_Y)), yhi = int(floor((ny.y * 0.5 + 0.5) * GRID_Y));

  if (zhi < 0 || zlo > int(GRID_Z)-1) return false;           // fully outside grid on any axis
  if (xhi < 0 || xlo > int(GRID_X)-1) return false;
  if (yhi < 0 || ylo > int(GRID_Y)-1) return false;

  lo = uvec3(clamp(xlo, 0, int(GRID_X)-1), clamp(ylo, 0, int(GRID_Y)-1), clamp(zlo, 0, int(GRID_Z)-1));
  hi = uvec3(clamp(xhi, 0, int(GRID_X)-1), clamp(yhi, 0, int(GRID_Y)-1), clamp(zhi, 0, int(GRID_Z)-1));
  return true;
}

/** Link light li into every froxel in [lo,hi], reserving the block with a single atomic. */
void assignLightToFroxels(uint li, uvec3 lo, uvec3 hi) {
  uint total = (hi.z - lo.z + 1u) * (hi.y - lo.y + 1u) * (hi.x - lo.x + 1u);
  uint base  = atomicAdd(cursor[0].cursor, total);
  if (base >= ubo.indexBufferLength) return;
  if (base + total > ubo.indexBufferLength) total = ubo.indexBufferLength - base;  // clamp tail on overflow

  uint slot = base;
  for (uint z = lo.z; z <= hi.z; ++z) { for (uint y = lo.y; y <= hi.y; ++y) {
    uint rowBase = clusterId(0u, y, z);
    for (uint x = lo.x; x <= hi.x; ++x) {
      if (slot >= base + total) break;
      indices[slot].light = li;
      indices[slot].next  = atomicExchange(head[rowBase + x].head, slot);   // per-cluster linked list
      ++slot;
    }
  } }
}

void main() {
  uint li = gl_GlobalInvocationID.x;
  if (li >= ubo.nlights) return;

  Light L = lightSSBO.lights[li];
  if (L.properties.w == 0.0 || L.position.w == 0.0) return; // Disabled or directional: a global light, not clustered

  uvec3 lo, hi;
  if (!sphereFroxelRange(lightBoundSphere(L), lo, hi)) return; // off-grid / behind camera
  assignLightToFroxels(li, lo, hi);
}
