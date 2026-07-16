// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

layout(input_attachment_index = 0, binding = 12) uniform subpassInput accumInput;
layout(input_attachment_index = 1, binding = 13) uniform subpassInput revealInput;

layout(location = 0) out vec4 outColor;

void main() {
  vec4 accum = subpassLoad(accumInput);
  float reveal = subpassLoad(revealInput).r;

  // Weighted average colour = sum(color*a*w) / sum(a*w); coverage = 1 - product(1-a)
  vec3 avgColor = accum.rgb / max(accum.a, 1e-5);
  outColor = vec4(avgColor, 1.0 - reveal);   // src-alpha blended over the resolved HDR
}
