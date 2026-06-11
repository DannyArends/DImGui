// DImGui - FRAGMENT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "functions.glsl"
#include "samplers.glsl"

// Per Fragment input attributes
layout(location = 0) in vec4 fragPosWorld;              /// Fragment Position (in world space)
layout(location = 1) in vec4 fragColor;                 /// Fragment Color
layout(location = 2) in vec3 fragNormal;                /// Fragment Normal
layout(location = 3) in vec2 fragTexCoord;              /// Texture coordinates
layout(location = 4) flat in ivec2 fragInstance;        /// [Mesh, Material]
layout(location = 5) in mat3 fragTBN;                   /// Fragment: Tangent, Bitangent, Normal matrix

// Fragment output (to post-processing shader)
layout(location = 0) out vec4 outColor;

void main() {
  Mesh mesh = meshSSBO.meshes[uint(fragInstance[0])];
  Material mat = materialSSBO.materials[uint(mesh.mid)];
  if(fragInstance[1] >= 0) mat = materialSSBO.materials[uint(fragInstance[1])];

  vec3 baseColor = fragColor.rgb;

  if (!(TOPOLOGY == 1) && mat.tid >= 0) {
    vec4 texSample = texture(textureSampler[mat.tid], fragTexCoord).rgba;
    if(ALPHA_TEST && texSample.a < 0.2f) discard;
    baseColor *= texSample.rgb;
  }
  if (ALPHA_TEST && mat.oid >= 0 && texture(textureSampler[mat.oid], fragTexCoord).a < 0.4f) discard;

  if (ubo.lightingMode == 0u) { outColor = vec4(baseColor * 0.2, 1.0); return; }

  vec3 normalForLighting = normalize(fragNormal);
  /// Surface normalForLighting
  //outColor = vec4(normalForLighting * 0.5 + 0.5, 1.0); return;
  if (mat.nid >= 0) {
    normalForLighting = getBumpedNormal(ubo.position.xyz, fragPosWorld.xyz, mat.nid, fragTexCoord, fragTBN);
  }
  /// normalForLighting after bump mapping
  // outColor = vec4(normalForLighting * 0.5 + 0.5, 1.0); return;

  /// Shadow cast by light 0
  // outColor = vec4(calculateShadow(lightSSBO.lights[0].lightProjView * fragPosWorld, 0, 0.05), 1.0); return;
  vec3 surfaceColor = baseColor * 0.01;
  bool useShadows = ubo.lightingMode == 2u;

  // Directional/global lights (position.w == 0, not clustered)
  for (int i = 0; i < ubo.nlights; ++i) {
    if (lightSSBO.lights[i].properties.w == 0.0) continue; // disabled
    if (lightSSBO.lights[i].position.w != 0.0) continue; // point lights via clusters below
    surfaceColor += shadeLight(uint(i), baseColor, fragPosWorld, normalForLighting, useShadows);
  }

  // Point lights via this fragment's froxel linked list
  float viewDepth = -(ubo.view * fragPosWorld).z;
  uint cid = froxelIndex(gl_FragCoord.xy, viewDepth);
  for (uint n = head[cid].head; n != NIL; n = indices[n].next) {
    surfaceColor += shadeLight(indices[n].light, baseColor, fragPosWorld, normalForLighting, useShadows);
  }
  outColor = vec4(surfaceColor, 1.0);
}

