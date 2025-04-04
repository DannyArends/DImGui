// Wavefront FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 1) uniform sampler2D texureSampler;

layout(push_constant) uniform constants {
  mat4 model;
  int oId;
  int tID;
} pc;

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {
  vec4 color = texture(texureSampler, fragTexCoord).rgba;
  vec3 blended = fragColor.rgb * color.rgb;
  if(color.a < 0.2f) discard;
  outColor = vec4(blended, color.a);
}
