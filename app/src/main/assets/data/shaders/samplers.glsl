// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef SAMPLERS_GLSL
#define SAMPLERS_GLSL

/// Samplers/Images
#define BINDING_TEXTURES          5
#define BINDING_SHADOWMAP         6

/// Samplers/Images
layout(binding = BINDING_TEXTURES) uniform sampler2D textureSampler[];
layout(binding = BINDING_SHADOWMAP) uniform sampler2DShadow shadowMap[];

// Bump mapped normal
vec3 getBumpedNormal(vec3 cameraPos, vec3 fragPos, int fragNid, vec2 fragTexCoord, mat3 fragTBN){
  vec3 normalFromMap = texture(textureSampler[fragNid], fragTexCoord).rgb;
  normalFromMap = normalize(normalFromMap * 2.0 - 1.0);

  vec3 finalNormal = normalize(fragTBN * normalFromMap);
  return(finalNormal);
}

// Function to calculate the shadow factor
float calculateShadow(vec4 position, uint i) {
  vec3 projCoords = position.xyz / position.w;
  projCoords.xy = projCoords.xy * 0.5 + 0.5;

  if (projCoords.x < 0.0 || projCoords.x > 1.0 || projCoords.y < 0.0 || projCoords.y > 1.0 || projCoords.z < 0.0 || projCoords.z > 1.0){
    return 1.0; // Not in shadow
  }

  float shadowFactor = 0.0;
  vec2 texelSize = vec2(ubo.shadowTexelSize);
  int sampleCount = 1;
  float range = 1.0;

  // PCF sampling loop
  for (int x = -sampleCount; x <= sampleCount; ++x) {
    for (int y = -sampleCount; y <= sampleCount; ++y) {
      vec2 offset = vec2(x, y) * texelSize * range;
      shadowFactor += texture(shadowMap[i], vec3(projCoords.xy + offset, projCoords.z));
    }
  }
  return shadowFactor / float((2 * sampleCount + 1) * (2 * sampleCount + 1));
}

// Per-light shading: ambient + shadowed direct contribution
vec3 shadeLight(uint idx, vec3 baseColor, vec4 fragPosWorld, vec3 normal, bool useShadows) {
  Light light = lightSSBO.lights[idx];
  vec3 contribution = illuminate(light, baseColor, fragPosWorld.xyz, normal, ubo.position.xyz);
  vec3 ambient = light.intensity.rgb * baseColor * light.properties[0];
  vec3 direct  = contribution - ambient;
  if (useShadows) direct *= calculateShadow(light.lightProjView * fragPosWorld, idx);
  return ambient + direct;
}

#endif // SAMPLERS_GLSL
