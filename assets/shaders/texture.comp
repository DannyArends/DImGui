// DImGui - COMPUTE SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

layout(local_size_x = 16, local_size_y = 16) in;              // Size of a workgroup for compute
layout(rgba16f, set = 0, binding = 0) uniform image2D image;  // Image

// A single iteration of Bob Jenkins' One-At-A-Time hashing algorithm.
uint hash(uint x) {
  x += ( x << 10u );
  x ^= ( x >>  6u );
  x += ( x <<  3u );
  x ^= ( x >> 11u );
  x += ( x << 15u );
  return x;
}

uint hash(uvec2 v) { return hash(v.x ^ hash(v.y)); }

// Construct a float with half-open range [0:1] using low 23 bits.
float floatConstruct(uint m) {
  const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
  const uint ieeeOne = 0x3F800000u;      // 1.0 in IEEE binary32

  m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
  m |= ieeeOne;                          // Add fractional part to 1.0

  return uintBitsToFloat(m) - 1.0;       // Range [0:1]
}

float random(vec2 v) { return floatConstruct(hash(floatBitsToUint(v))); }

void main(){
  ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);
  float rand = random(texelCoord);
  imageStore(image, texelCoord, vec4(vec3(rand), 1.0));
}
