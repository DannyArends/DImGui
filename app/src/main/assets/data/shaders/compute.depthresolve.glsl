// DImGui - Cull shader
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

layout(local_size_x = 8, local_size_y = 8) in;

layout(binding = 0) uniform sampler2DMS depthSampler;                   // the only sampler2DMS left in the codebase
layout(binding = 1, r32f) uniform writeonly image2D depthResolved;

void main() {
  ivec2 px = ivec2(gl_GlobalInvocationID.xy);
  ivec2 size = textureSize(depthSampler);
  if(px.x >= size.x || px.y >= size.y) return;
  imageStore(depthResolved, px, vec4(texelFetch(depthSampler, px, 0).r));  // sample 0; swap for min-of-N if wanted
}

