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
layout(location = 4) flat in ivec2 fragInstance;  /// [Mesh, Material, Texture override]
layout(location = 5) in mat3 fragTBN;

layout(location = 0) out vec4 outColor;

void main() {
  Mesh mesh = meshSSBO.meshes[uint(fragInstance[0])];
  Material mat = materialSSBO.materials[uint(mesh.mid)];

  vec3 baseColor = fragColor.rgb;
  if(mat.oid >= 0) {
    float alpha = texture(textureSampler[mat.oid], fragTexCoord).a;
    if(alpha < 0.2f) discard;
  }

  bool useTexOverride = fragInstance[1] >= 0;
  int tid = useTexOverride ? fragInstance[1] : mat.tid;
  if(tid >= 0){
    vec4 texSample = texture(textureSampler[tid], fragTexCoord).rgba;
    if(texSample.a < 0.2f) discard;
    baseColor = useTexOverride ? texSample.rgb : baseColor * texSample.rgb;
  }

  vec3 normalForLighting = fragNormal;
  if(mat.nid >= 0) {
    normalForLighting = getBumpedNormal(ubo.position.xyz, fragPosWorld.xyz, mat.nid, fragTexCoord, fragTBN);
  }

  vec3 lightColor = baseColor * 0.001;
  if (ubo.lightingMode == 0u) { outColor = vec4(baseColor * 0.2, 1.0); return; }
  bool useShadows = ubo.lightingMode == 2u;
  for(int i = 0; i < ubo.nlights; ++i) {
    Light light = lightSSBO.lights[i];
    vec3 lightContribution = illuminate(light, baseColor, fragPosWorld.xyz, normalForLighting, ubo.position.xyz);
    if(useShadows && any(greaterThan(lightContribution, vec3(0.01)))) {
      lightContribution *= calculateShadow(light.lightProjView * fragPosWorld, i);
    }
    lightColor += lightContribution;
  }
  outColor = vec4(lightColor, 1.0);
}
