// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

layout(constant_id = 0) const int SAMPLES = 2;   // MSAA sample count, fed by resolve pipeline

layout(input_attachment_index = 0, binding = 12) uniform subpassInputMS accumInput;
layout(input_attachment_index = 1, binding = 13) uniform subpassInputMS revealInput;

layout(location = 0) out vec4 outColor;

void main() {
  vec4 accum = vec4(0.0);
  float reveal = 0.0;
  for (int s = 0; s < SAMPLES; ++s) {
    accum  += subpassLoad(accumInput, s);
    reveal += subpassLoad(revealInput, s).r;
  }
  accum  /= float(SAMPLES);
  reveal /= float(SAMPLES);

  vec3 avgColor = accum.rgb / max(accum.a, 1e-5);
  outColor = vec4(avgColor, 1.0 - reveal);   // resolved: per-sample averaged, then composited
}
