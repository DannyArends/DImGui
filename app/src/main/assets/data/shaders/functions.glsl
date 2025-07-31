// DImGui - Function Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef FUNCTIONS_GLSL
#define FUNCTIONS_GLSL

#include "structures.glsl"

// Function to calculate vector position after animation
vec4 animate(vec4 inPos, uvec4 inBones, vec4 inWeights) {
  bool hasbone = false;
  vec4 bonepos = vec4(0.0f, 0.0f, 0.0f, 0.0f);
  for (int i = 0; i < 4; i++) {
    float weight = inWeights[i];
    if(weight > 0.0f) {
      uint boneID = inBones[i];
      mat4 boneTransform = boneSSBO.transforms[boneID].offset;
      bonepos += (boneTransform * inPos) * weight;
      hasbone = true;
    }
  }
  vec4 finalPosition = inPos;
  if(hasbone){ finalPosition = bonepos; }
  return(finalPosition);
}

// Function to calculate the shadow factor
float calculateShadow(vec4 position, uint i) {
  vec3 projCoords = ((position.xyz / position.w) * 0.5) + 0.5;

  if (projCoords.x < 0.0 || projCoords.x > 1.0 ||
      projCoords.y < 0.0 || projCoords.y > 1.0 ||
      projCoords.z < 0.0 || projCoords.z > 1.0){
    return 1.0; // Not in shadow
  }

  float shadowFactor = 0.0;
  vec2 texelSize = 1.0 / vec2(textureSize(shadowMap[i], 0));
  int sampleCount = 2;
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

// Our illumination function
vec3 illuminate(Light light, vec3 baseColor, vec3 position, vec3 normal) {
  float attenuation = 1.0;
  vec3 s;
  if (light.position.w == 0.0) {
    // Directional lighting
    s = normalize( light.position.xyz );
  } else {
    // Point lighting
    s = normalize( light.position.xyz - position );
    float l = length( light.position.xyz - position );
    attenuation = 1.0 / (light.properties[1] + pow(l, 2.0));

    // Cone lighting
    float lAngle = degrees(acos(dot(-s, normalize(light.direction.xyz))));
    float outerConeAngle = light.properties[2];
    float innerConeAngle =outerConeAngle / 2.0f;

    float coneFactor = smoothstep(outerConeAngle, innerConeAngle, lAngle);
    attenuation *= coneFactor;
  }
  float sDotN = max( dot( s, normal ), 0.0 );

  vec3 ambientCol = light.intensity.rgb * baseColor * light.properties[0];
  vec3 diffuseCol = light.intensity.rgb * baseColor * sDotN;
  return ambientCol + attenuation * diffuseCol;
}

vec3 getBumpedNormal(vec3 cameraPos, vec3 fragPos, int fragNid, vec2 fragTexCoord, mat3 fragTBN){
  vec3 normalFromMap = texture(texureSampler[fragNid], fragTexCoord).rgb;
  normalFromMap = normalize(normalFromMap * 2.0 - 1.0);
  normalFromMap = vec3(normalFromMap.xy * 2.0f, normalFromMap.z);

  vec3 finalNormal = normalize(fragTBN * normalFromMap);
  return(finalNormal);
}

#endif // FUNCTIONS_GLSL
