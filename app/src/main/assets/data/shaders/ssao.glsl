// DImGui - SSAO COMPUTE SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html
#version 460
layout(local_size_x = 8, local_size_y = 8) in;

layout(binding = 0) uniform sampler2DMS depthSampler;          // scene depth (MSAA), sample 0
layout(binding = 1, rgba8) uniform writeonly image2D ssaoOut;  // auto-provisioned by reflection
layout(binding = 2) uniform SSAO {
  mat4 proj;
  mat4 projInv;
  vec4 kernel[32];   // view-space hemisphere samples in .xyz
  vec4 params;       // x=radius  y=bias  z=power  w=kernelSize
} u;

vec3 viewPos(ivec2 px, ivec2 size) {                            // reconstruct view-space position from depth
  float d = texelFetch(depthSampler, px, 0).r;
  vec2 ndc = (vec2(px) + 0.5) / vec2(size) * 2.0 - 1.0;
  vec4 v = u.projInv * vec4(ndc, d, 1.0);
  return v.xyz / v.w;
}

void main() {
  ivec2 px = ivec2(gl_GlobalInvocationID.xy);
  ivec2 size = imageSize(ssaoOut);
  if (px.x >= size.x || px.y >= size.y) return;

  vec3 P  = viewPos(px, size);
  vec3 Px = viewPos(px + ivec2(1,0), size);                     // normals from neighbour depths (no dFdx in compute)
  vec3 Py = viewPos(px + ivec2(0,1), size);
  vec3 N  = normalize(cross(Px - P, Py - P));

  float a = fract(sin(dot(vec2(px), vec2(12.9898, 78.233))) * 43758.5453);   // per-pixel rotation, no noise texture
  vec3 rnd = vec3(cos(6.2831853 * a), sin(6.2831853 * a), 0.0);
  vec3 T = normalize(rnd - N * dot(rnd, N));
  mat3 TBN = mat3(T, cross(N, T), N);

  int K = 32;
  float occ = 0.0;
  for (int i = 0; i < K; ++i) {
    vec3 s = P + (TBN * u.kernel[i].xyz) * u.params.x;          // sample point in view space
    vec4 o = u.proj * vec4(s, 1.0); o.xyz /= o.w;
    ivec2 spx = ivec2((o.xy * 0.5 + 0.5) * vec2(size));
    if (any(lessThan(spx, ivec2(0))) || any(greaterThanEqual(spx, size))) continue;
    float sd = viewPos(spx, size).z;
    float rangeCheck = smoothstep(0.0, 1.0, u.params.x / abs(P.z - sd));
    occ += (sd >= s.z + u.params.y ? 1.0 : 0.0) * rangeCheck;
  }
  float ao = pow(1.0 - occ / float(K), u.params.z);
  ao = mix(1.0, ao, u.params.w);                 // params.w gates SSAO on/off
  imageStore(ssaoOut, px, vec4(ao));
}
