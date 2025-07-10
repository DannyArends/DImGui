// DImGui - Function Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef FUNCTIONS_GLSL
#define FUNCTIONS_GLSL

#include "structures.glsl"

/// Shader Storage Buffer Objects
layout (std140, binding = BINDING_BONES_SSBO) readonly buffer BoneMatrices {
    Bone transforms[];
} boneSSBO;

layout (std140, binding = BINDING_MESH_SSBO) readonly buffer MeshMatrices {
    Mesh meshes[];
} meshSSBO;

layout (std140, binding = BINDING_LIGHT_SSBO) readonly buffer LightMatrices {
    Light lights[];
} lightSSBO;

/// Samplers/Images
layout(binding = BINDING_TEXTURES) uniform sampler2D texureSampler[];
layout(binding = BINDING_SHADOWMAP) uniform sampler2DShadow shadowMap[];

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
vec3 illuminate(Light light, vec4 baseColor, vec4 position, vec3 normal) {
  float attenuation = 1.0;
  vec3 s;
  if (light.position.w == 0.0) {
    // Directional lighting
    s = normalize( light.position.xyz );
  } else {
    // Point lighting
    s = normalize( light.position.xyz - position.xyz );
    float l = abs(length( light.position.xyz - position.xyz ));
    attenuation = 1.0 / (1.0 + light.properties[1] * pow(l, 2.0));

    // Cone lighting
    float lAngle = degrees(acos(dot(-s, normalize(light.direction.xyz))));
    if (lAngle >= light.properties[2] - 1.0f) { attenuation = 0.3; }
    if (lAngle >= light.properties[2]) { attenuation = 0.0; }
  }
  vec3 r = reflect( -s, normal );
  float sDotN = max( dot( s, normal ), 0.0 );

  vec3 ambientCol = light.intensity.rgb * baseColor.rgb * light.properties[0];
  vec3 diffuseCol = light.intensity.rgb * baseColor.rgb * sDotN;
  vec3 specularCol = vec3( 0.0 );
  if (sDotN > 0.0 && light.position.w > 0.0) {
    specularCol = light.intensity.rgb * baseColor.rgb * pow(max(dot(s, r), 0.0), baseColor.a);
  }
  return ambientCol + attenuation * (diffuseCol + specularCol);
}

vec3 calculateBump(Light light, vec3 cameraPos, vec3 fragPos, int fragNid, vec2 fragTexCoord, mat3 fragTBN){
  // 1. Get the normal from the normal map
  vec3 normalFromMap = texture(texureSampler[fragNid], fragTexCoord).rgb;
  normalFromMap = normalize(normalFromMap * 2.0 - 1.0);
  vec3 finalNormal = normalize(fragTBN * normalFromMap);

  // 3. Simple Lambertian (diffuse) lighting with an ambient term
  vec3 ambientColor = vec3(0.5);
  vec3 lightDir = normalize(-light.direction.xyz); // Light direction points towards the light source

  // Diffuse component
  float diff = max(dot(finalNormal, lightDir), 0.0);
  vec3 diffuseColor = light.intensity.xyz * diff;

  // Specular component (Blinn-Phong for simplicity)
  vec3 viewDir = normalize(cameraPos - fragPos);
  vec3 halfVec = normalize(lightDir + viewDir);
  float spec = pow(max(dot(finalNormal, halfVec), 0.0), 32.0); // 32.0 is shininess
  vec3 specularColor = light.intensity.xyz * spec * 0.5; // Reduce specular intensity

  return(ambientColor + diffuseColor + specularColor);
}

#endif // FUNCTIONS_GLSL
