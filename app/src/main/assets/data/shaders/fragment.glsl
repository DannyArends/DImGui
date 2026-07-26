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
layout(location = 5) in vec3 fragViewPos;               /// View-space position (froxel lookup)
layout(location = 6) in mat3 fragTBN;                   /// Fragment: Tangent, Bitangent, Normal matrix

// Fragment output: normal path writes location 0; WBOIT path writes accum(0) + revealage(1)
layout(location = 0) out vec4 outColor;
layout(location = 1) out float outRevealage;

/// Emit final shaded color: standard alpha-over (location 0) or WBOIT accumulation (accum + revealage)
void writeOutput(vec3 color, float alpha) {
  if (WBOIT) {
    float d = -(ubo.view * fragPosWorld).z;                              // linear distance from camera
    float zNorm = clamp((log2(d) * ubo.clusterCfg.x + ubo.clusterCfg.y) / float(GRID_Z), 0.0, 1.0);
    float w = alpha * clamp(0.3 / (1e-5 + pow(zNorm, 4.0)), 1e-2, 3e3);  // near (zNorm→0) weighted high, far low
    outColor = vec4(color * alpha * w, alpha * w);   // accum: premultiplied, weighted
    outRevealage = alpha;                            // revealage: blended as product(1-a) via pipeline blend
  } else { outColor = vec4(color, alpha); }
}

void main() {
  Mesh mesh = meshSSBO.meshes[uint(fragInstance[0])];
  Material mat = materialSSBO.materials[uint(mesh.mid)];
  if(fragInstance[1] >= 0) mat = materialSSBO.materials[uint(fragInstance[1])];

  // Color RGB & alpha
  vec3 rgb = fragColor.rgb; float alpha = fragColor.a;

  // Multiply texture to basecolor & adjust alpha outside of the DEPTH_PASS
  if(!DEPTH_PASS && !(TOPOLOGY == 1) && mat.tid >= 0) {
    vec4 texSample = texture(textureSampler[mat.tid], fragTexCoord).rgba;
    rgb *= texSample.rgb; alpha = texSample.a;
  }

  // If we do alpha testing: Opacity texture alpha & SDF override
  if(ALPHA_TEST) {
    if (mat.oid >= 0) { alpha = texture(textureSampler[mat.oid], fragTexCoord).a; }
    if (SDF) {
      float adj = fwidth(alpha) * 0.1;
      alpha = smoothstep(0.5 - adj, 0.5 + adj, alpha);
    }
    if (alpha < 0.05f) discard; // Discard <.05

    // If we're depth testing we discard transparent fragments
    if(DEPTH_PASS) { if(alpha < 0.99) { discard; } return; }
    // If we're WBOIT testing we discard opaque fragments, if not transparant ones
    if(WBOIT) { if(alpha >= 0.99 && !SDF){ discard; } }else{ if (alpha <  0.99 ||  SDF){ discard; } }
  }

  // Lighting only runs when we are not depth testing
  if(!DEPTH_PASS) {
    float ao = (!SDF && useSSAO && !WBOIT) ? texture(ssaoSampler, gl_FragCoord.xy / ubo.clusterCfg.zw).r : 1.0;

    // Lighting mode 0: Return base color
    if(ubo.lightingMode == 0u) { writeOutput(rgb * 0.2 * ao, alpha); return; }

    vec3 normalForLighting = normalize(fragNormal);
    /// Surface normalForLighting
    //outColor = vec4(normalForLighting * 0.5 + 0.5, 1.0); return;
    if(NORMAL_MAPPED && mat.nid >= 0) {
      normalForLighting = getBumpedNormal(ubo.position.xyz, fragPosWorld.xyz, mat.nid, fragTexCoord, fragTBN);
    }
    /// normalForLighting after bump mapping
    // outColor = vec4(normalForLighting * 0.5 + 0.5, 1.0); return;

    vec3 surfaceColor = rgb * 0.01;
    bool useShadows = ubo.lightingMode == 2u;
    float shadowDist = length(fragPosWorld.xz - ubo.shadowCentre.xz);

    // Directional/global lights (position.w == 0, not clustered)
    for(int i = 0; i < ubo.nlights; ++i) {
      if(lightSSBO.lights[i].properties.w == 0.0) continue; // disabled
      if(lightSSBO.lights[i].position.w != 0.0) continue; // point lights via clusters below
      surfaceColor += shadeLight(uint(i), rgb, fragPosWorld, normalForLighting, shadowDist, useShadows);
    }

    // Point lights via this fragment's froxel linked list
    vec4 clip = ubo.proj * vec4(fragViewPos, 1.0);
    uint cid = froxelIndex((clip.xy / clip.w) * 0.5 + 0.5, -fragViewPos.z);

    for(uint n = head[cid].head; n != NIL; n = indices[n].next) {
      surfaceColor += shadeLight(indices[n].light, rgb, fragPosWorld, normalForLighting, shadowDist, useShadows);
    }

    // Screen-space ambient occlusion: opaque only (SDF/transparent geometry has no valid depth, must not receive AO)
    writeOutput(surfaceColor * ao, alpha);
  }
}

