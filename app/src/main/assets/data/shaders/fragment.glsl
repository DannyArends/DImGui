// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

struct Light {
  vec4 position;
  vec4 intensity;
  vec4 direction;
  vec4 properties;    // [ambient, attenuation, angle]
};

struct Bone {
  mat4 offset;
};

layout(std140, binding = 0) uniform UniformBufferObject {
    vec4 position;    // Scene Camera Position
    mat4 scene;       // Scene Camera adjustment
    mat4 view;        // View matrix
    mat4 proj;        // Projection matrix
    mat4 ori;         // Screen orientation
    Light[4] lights;  // Scene lights
    uint nlights;     // Number of actual lights
} ubo;

layout (std140, binding = 1) readonly buffer BoneMatrices {
    Bone transforms[];
} boneSSBO;

layout(binding = 2) uniform sampler2D texureSampler[];
layout(binding = 3) uniform sampler2DShadow shadowMap;

/* layout(std140, binding = 4) uniform LightSpaceUBO {
    mat4 lightSpaceMatrix;
} lightUbo; */

layout(location = 0) in vec3 fragPosWorld;
layout(location = 1) in vec4 fragPosLightSpace;
layout(location = 2) in vec4 fragColor;
layout(location = 3) in vec3 fragNormal;
layout(location = 4) in vec2 fragTexCoord;
layout(location = 5) flat in int fragTid;
layout(location = 6) flat in int fragNid;
layout(location = 7) in mat3 fragTBN;

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

vec3 calculateBump(){
  // 1. Get the normal from the normal map
  vec3 normalFromMap = texture(texureSampler[fragNid], fragTexCoord).rgb;
  normalFromMap = normalize(normalFromMap * 2.0 - 1.0);
  vec3 finalNormal = normalize(fragTBN * normalFromMap);

  // 3. Simple Lambertian (diffuse) lighting with an ambient term
  vec3 ambientColor = vec3(0.5);
  vec3 lightDir = normalize(-ubo.lights[0].direction.xyz); // Light direction points towards the light source

  // Diffuse component
  float diff = max(dot(finalNormal, lightDir), 0.0);
  vec3 diffuseColor = ubo.lights[0].intensity.xyz * diff;

  // Specular component (Blinn-Phong for simplicity)
  vec3 viewDir = normalize(ubo.position.xyz - fragPosWorld);
  vec3 halfVec = normalize(lightDir + viewDir);
  float spec = pow(max(dot(finalNormal, halfVec), 0.0), 32.0); // 32.0 is shininess
  vec3 specularColor = ubo.lights[0].intensity.xyz * spec * 0.5; // Reduce specular intensity

  return(ambientColor + diffuseColor + specularColor);
}

void main() {
  // Sample the base color
  vec3 baseColor = fragColor.rgb;
  if(fragTid >= 0){
    vec4 texColor = texture(texureSampler[fragTid], fragTexCoord).rgba;
    if(texColor.a < 0.2f) discard;
    baseColor = fragColor.rgb * texColor.rgb;
  }

  // Bump map
  vec3 adjustment = vec3(1.0f);
  if(fragNid >= 0) {
    adjustment = calculateBump();
 }
  // Compute shadow factor
  float shadowFactor = calculateShadow();
  outColor = vec4(baseColor * adjustment * shadowFactor, 1.0);
  //outColor = vec4(fragTexCoord[0], fragTexCoord[1], 0.0f, 1.0f);
}
