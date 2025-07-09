// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "structures.glsl"
#include "functions.glsl"

layout(std140, binding = BINDING_SCENE_UBO) uniform UniformBufferObject {
    vec4 position;    // Scene Camera Position
    mat4 scene;       // Scene Camera adjustment
    mat4 view;        // View matrix
    mat4 proj;        // Projection matrix
    mat4 ori;         // Screen orientation
} ubo;

layout(std140, binding = BINDING_LIGHT_UBO) uniform LightSpaceMatrices {
    mat4 lightProjView;
    mat4 scene;           /// Scene matrix (currently, just and Identity matrix)
    uint nlights;         /// Number of actual lights
} lightUbo;

layout(location = 0) in vec4 fragPosWorld;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec2 fragTexCoord;
layout(location = 4) flat in int fragTid;
layout(location = 5) flat in int fragNid;
layout(location = 6) in mat3 fragTBN;

layout(location = 0) out vec4 outColor;

void main() {
  vec3 baseColor = fragColor.rgb;
  if(fragTid >= 0){ // Modify by the texture
    vec4 texColor = pow(texture(texureSampler[fragTid], fragTexCoord).rgba, vec4(2.2));
    if(texColor.a < 0.2f) discard;
    baseColor = baseColor * texColor.rgb;
  }

  vec3 lightColor = vec3(0.0f);
  for(int i = 0; i < lightUbo.nlights; ++i) {
    lightColor += illuminate(lightSSBO.lights[i], vec4(baseColor, 1.0f), fragPosWorld, fragNormal);
  }

  /// Bump map adjustment
  vec3 adjustment = vec3(1.0f);
  if(fragNid >= 0) {
    adjustment = calculateBump(lightSSBO.lights[0], ubo.position.xyz, fragPosWorld.xyz, fragNid, fragTexCoord, fragTBN);
  }

  /// Compute and apply shadow factor
  float shadowFactor = calculateShadow(lightUbo.lightProjView * fragPosWorld);
  outColor = vec4(pow(lightColor * adjustment * shadowFactor, vec3(1.0/2.2)), 1.0);
}
