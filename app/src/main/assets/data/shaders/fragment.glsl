// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

layout(binding = 2) uniform sampler2D texureSampler[];

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragTexCoord;
layout(location = 3) flat in int fragTid;

layout(location = 0) out vec4 outColor;

void main() {
  if(fragTid >= 0){
    vec4 color = texture(texureSampler[fragTid], fragTexCoord).rgba;
    vec3 blended = fragColor.rgb * color.rgb;
    if(color.a < 0.2f) discard;
    outColor = vec4(blended, color.a);
  }else{
    outColor = fragColor;
  }
//outColor = vec4(fragTexCoord[0], fragTexCoord[1], 0.0f, 1.0f);
}

