// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

layout(binding = 2) uniform sampler2D texureSampler[];

layout(std140, binding = 3) uniform LightSpaceUBO {
    mat4 lightSpaceMatrix;
} lightUbo;

layout(binding = 4) uniform sampler2DShadow shadowMap;

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragTexCoord;
layout(location = 3) flat in int fragTid;
layout(location = 4) in vec3 fragPosWorld;
layout(location = 5) in vec4 fragPosLightSpace;

layout(location = 0) out vec4 outColor;

// Function to calculate the shadow factor
float calculateShadow() {
  vec3 projCoords = ((fragPosLightSpace.xyz / fragPosLightSpace.w) * 0.5) + 0.5;

  if (projCoords.x < 0.0 || projCoords.x > 1.0 ||
      projCoords.y < 0.0 || projCoords.y > 1.0 ||
      projCoords.z < 0.0 || projCoords.z > 1.0){
    return 1.0; // Not in shadow
  }

  float bias = 0.001;
  float shadow = texture(shadowMap, vec3(projCoords.xy, projCoords.z));
  return shadow;
}


void main() {
  vec3 finalFragmentColor;
  if(fragTid >= 0){
    vec4 texColor = texture(texureSampler[fragTid], fragTexCoord).rgba;
    if(texColor.a < 0.2f) discard;
    //outColor = vec4(blended, color.a);
    finalFragmentColor = fragColor.rgb * texColor.rgb;
  }else{
    //outColor = fragColor;
    finalFragmentColor = fragColor.rgb;
  }

  float shadowFactor = calculateShadow();
  outColor = vec4(finalFragmentColor * shadowFactor, 1.0);
  //outColor = vec4(fragTexCoord[0], fragTexCoord[1], 0.0f, 1.0f);
}

