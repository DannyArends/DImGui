// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "structures.glsl"
#include "functions.glsl"

layout(std140, binding = BINDING_SCENE_UBO) uniform UniformBufferObject {
  vec4 position;    /// Scene Camera Position
  mat4 scene;       /// Scene Camera adjustment
  mat4 view;        /// View matrix
  mat4 proj;        /// Projection matrix
  mat4 ori;         /// Screen orientation
  uint nlights;     /// Number of actual lights
} ubo;

layout(location = 0) in vec4 fragPosWorld;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec2 fragTexCoord;
layout(location = 4) flat in uint fragMesh;
layout(location = 5) in mat3 fragTBN;

layout(location = 0) out vec4 outColor;

void main() {
  vec3 baseColor = fragColor.rgb;
  if(meshSSBO.meshes[fragMesh].oid >= 0) { // We have an opacity texture
    float alpha = texture(texureSampler[meshSSBO.meshes[fragMesh].oid], fragTexCoord).a;
    if(alpha < 0.2f) discard;
  }

  if(meshSSBO.meshes[fragMesh].tid >= 0){ // Modify by the texture
    vec4 texSample = texture(texureSampler[meshSSBO.meshes[fragMesh].tid], fragTexCoord).rgba;
    if(texSample.a < 0.2f) discard;
    baseColor = baseColor * pow(texSample, vec4(2.2)).rgb;
  }

  vec3 normalForLighting = fragNormal;
  if(meshSSBO.meshes[fragMesh].nid >= 0) { // Bump if a normal map is active for this fragment
    normalForLighting = getBumpedNormal(ubo.position.xyz, fragPosWorld.xyz, meshSSBO.meshes[fragMesh].nid, fragTexCoord, fragTBN);
  }

  // Compute lighting and shadows
  vec3 lightColor = vec3(0.0f);
  for(int i = 0; i < ubo.nlights; ++i) {
    vec3 lightContribution = illuminate(lightSSBO.lights[i], vec4(baseColor, 1.0f), fragPosWorld, normalForLighting);
    float shadowFactor = 1.0f;
    if(i > 0){
      shadowFactor = calculateShadow(lightSSBO.lights[i].lightProjView * fragPosWorld, i);
    }
    lightColor += (lightContribution * shadowFactor);
  }

  /// ReAdjust output
  outColor = vec4(pow(lightColor, vec3(1.0/2.2)), 1.0);
}
