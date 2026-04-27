// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "structures.glsl"
#include "functions.glsl"

layout(location = 0) in vec4 fragPosWorld;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec2 fragTexCoord;
layout(location = 4) flat in uvec2 fragInstance;  /// [Mesh, Material]
layout(location = 5) in mat3 fragTBN;

layout(location = 0) out vec4 outColor;

void main() {
  vec3 baseColor = fragInstance[1] > 0u ? fragColor.rgb * colorSSBO.colors[fragInstance[1]].color.rgb : fragColor.rgb;
  if(meshSSBO.meshes[fragInstance[0]].oid >= 0) { // We have an opacity texture
    float alpha = texture(textureSampler[meshSSBO.meshes[fragInstance[0]].oid], fragTexCoord).a;
    if(alpha < 0.2f) discard;
  }

  if(meshSSBO.meshes[fragInstance[0]].tid >= 0){ // Modify by the texture
    vec4 texSample = texture(textureSampler[meshSSBO.meshes[fragInstance[0]].tid], fragTexCoord).rgba;
    if(texSample.a < 0.2f) discard;
    baseColor = baseColor * texSample.rgb;
  }

  vec3 normalForLighting = fragNormal;
  if(meshSSBO.meshes[fragInstance[0]].nid >= 0) { // Bump if a normal map is active for this fragment
    normalForLighting = getBumpedNormal(ubo.position.xyz, fragPosWorld.xyz, meshSSBO.meshes[fragInstance[0]].nid, fragTexCoord, fragTBN);
  }

  // Compute lighting and shadows
  vec3 lightColor = baseColor * 0.001;
  if (ubo.lightingMode == 0u) {                        // Global illumination
    lightColor = baseColor * 0.2;
  } else if (ubo.lightingMode == 1u) {
    for(int i = 0; i < ubo.nlights; ++i)
      lightColor += illuminate(lightSSBO.lights[i], baseColor, fragPosWorld.xyz, normalForLighting, ubo.position.xyz);
  } else {
    for(int i = 0; i < ubo.nlights; ++i) {
      vec3 lightContribution = illuminate(lightSSBO.lights[i], baseColor, fragPosWorld.xyz, normalForLighting, ubo.position.xyz);
      float shadowFactor = calculateShadow(lightSSBO.lights[i].lightProjView * fragPosWorld, i);
      lightColor += lightContribution * shadowFactor;
    }
  }
  outColor = vec4(lightColor, 1.0);
}
