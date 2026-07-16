// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform sampler2D hdrSampler;
layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

vec3 tonemapACES(vec3 x) {
  float a = 2.51;
  float b = 0.03;
  float c = 2.43;
  float d = 0.59;
  float e = 0.14;
  return (x * (a * x + b)) / (x * (c * x + d) + e);
}

void main() {
  vec3 hdrColor = texture(hdrSampler, fragTexCoord).rgb;      // AO now applied in the opaque scene pass (gated !SDF)
  vec3 tonemappedColor = tonemapACES(hdrColor);               // Tone map
  outColor = vec4(pow(tonemappedColor, vec3(1.0 / 2.2)), 1.0);
}