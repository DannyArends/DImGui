// DImGui - SSAO COMPUTE SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

layout(local_size_x = 8, local_size_y = 8) in;

#ifdef MSAA
  layout(binding = 0) uniform sampler2DMS depthSampler;
#else
  layout(binding = 0) uniform sampler2D depthSampler;
#endif

layout(binding = 1, rgba8) uniform writeonly image2D ssaoOut;
layout(binding = 2) uniform SSAO {
  mat4 viewProj;                // ori * proj * view
  mat4 invViewProj;             // inverse(viewProj): clip -> world
  vec4 camPos;                  // camera world position (.xyz)
  vec4 kernel[SSAO_KERNEL];     // tangent-space hemisphere samples (.xyz)
  vec4 params;                  // x=radius(world units) y=bias z=power w=enable
} u;

vec3 worldPos(ivec2 px, ivec2 size) {
  float d = texelFetch(depthSampler, px, 0).r;
  vec2 ndc = (vec2(px) + 0.5) / vec2(size) * 2.0 - 1.0;
  vec4 w = u.invViewProj * vec4(ndc, d, 1.0);
  return w.xyz / w.w;
}

void main() {
  ivec2 outPx = ivec2(gl_GlobalInvocationID.xy);
  ivec2 outSize = imageSize(ssaoOut);
  if(outPx.x >= outSize.x || outPx.y >= outSize.y) return;
  #ifdef MSAA
    ivec2 size = textureSize(depthSampler);
  #else
    ivec2 size = textureSize(depthSampler, 0);
  #endif
  ivec2 px = ivec2((vec2(outPx) + 0.5) * vec2(size) / vec2(outSize));

  vec3 P  = worldPos(px, size);
  vec3 Pr = worldPos(px + ivec2(1, 0), size);
  vec3 Pl = worldPos(px - ivec2(1, 0), size);
  vec3 Pu = worldPos(px + ivec2(0, 1), size);
  vec3 Pd = worldPos(px - ivec2(0, 1), size);

  vec3 dX = (length(Pr - P) < length(Pl - P)) ? (Pr - P) : (P - Pl);
  vec3 dY = (length(Pu - P) < length(Pd - P)) ? (Pu - P) : (P - Pd);
  vec3 N  = normalize(cross(dX, dY));
  if(dot(N, u.camPos.xyz - P) < 0.0) N = -N;            // orient toward camera

  float a = fract(sin(dot(vec2(px), vec2(12.9898, 78.233))) * 43758.5453);
  vec3 rnd = vec3(cos(6.2831853 * a), sin(6.2831853 * a), 0.0);
  vec3 T = normalize(rnd - N * dot(rnd, N));
  mat3 TBN = mat3(T, cross(N, T), N);

  float camDist = length(u.camPos.xyz - P);
  float radius  = min(u.params.x, 0.05 * camDist);

  float occ = 0.0;
  for (int i = 0; i < SSAO_KERNEL; ++i) {
    vec3 s = P + (TBN * u.kernel[i].xyz) * radius;    // world-space sample point
    vec4 clip = u.viewProj * vec4(s, 1.0);
    if (clip.w <= 0.0) continue;
    vec2 suv = (clip.xy / clip.w) * 0.5 + 0.5;
    ivec2 spx = ivec2(suv * vec2(size));
    if (any(lessThan(spx, ivec2(0))) || any(greaterThanEqual(spx, size))) continue;

    vec3 surf = worldPos(spx, size);                      // real surface at that screen pixel
    float sampleDist = length(u.camPos.xyz - s);
    float surfaceDist = length(u.camPos.xyz - surf);
    // occluded when the real surface sits nearer the camera than the sample (sample is buried behind geometry)
    float rangeCheck = smoothstep(0.0, 1.0, radius / max(length(surf - P), 1e-4));
    occ += (surfaceDist < sampleDist - u.params.y ? 1.0 : 0.0) * rangeCheck;
  }
  float ao = pow(1.0 - occ / float(SSAO_KERNEL), u.params.z);
  ao = mix(1.0, ao, u.params.w);
  imageStore(ssaoOut, outPx, vec4(ao));
}
