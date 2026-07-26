// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef SAMPLERS_GLSL
#define SAMPLERS_GLSL

#extension GL_EXT_nonuniform_qualifier : enable

#define SHADOW_SKIP 0.02

/// Samplers/Images
#define BINDING_TEXTURES          5
#define BINDING_SHADOWMAP         6
#define BINDING_SSAO              11

/// Samplers/Images
layout(binding = BINDING_TEXTURES) uniform sampler2D textureSampler[];
layout(binding = BINDING_SHADOWMAP) uniform sampler2DShadow shadowMap[];
layout(binding = BINDING_SSAO) uniform sampler2D ssaoSampler;

// Bump mapped normal
vec3 getBumpedNormal(vec3 cameraPos, vec3 fragPos, int fragNid, vec2 fragTexCoord, mat3 fragTBN){
  vec3 normalFromMap = texture(textureSampler[nonuniformEXT(fragNid)], fragTexCoord).rgb;
  normalFromMap = normalize(normalFromMap * 2.0 - 1.0);

  vec3 finalNormal = normalize(fragTBN * normalFromMap);
  return(finalNormal);
}

// Sample one cascade slot; returns 1.0 (lit) if the fragment falls outside this slot's map.
float sampleSlot(vec4 fragPosWorld, int s) {
  vec4 position = lightUbo.slotVP[s] * fragPosWorld;
  vec3 pC = position.xyz / position.w;
  pC.xy = pC.xy * 0.5 + 0.5;
  if (pC.x < 0.0 || pC.x > 1.0 || pC.y < 0.0 || pC.y > 1.0 || pC.z < 0.0 || pC.z > 1.0) return 1.0;
  return texture(shadowMap[nonuniformEXT(s)], pC);
}

uint nCascades(Light light){
  return ((light.position.w == 0.0) ? uint(light.cull[2]) : 1u) - 1u;
}

float calculateShadow(vec4 fragPosWorld, Light light, float shadowDistance) {
  int first = int(light.cull[1]);
  if (first < 0) return 1.0;
  uint count = nCascades(light);

  // single-slot (point/spot): no cascade blend
  if (count == 0u) return sampleSlot(fragPosWorld, first);

  // pick cascade c by distance
  uint c = 0u;
  for (; c < count; ++c) { if (shadowDistance <= lightUbo.cascadeSplit[c]) break; }
  float shadow = sampleSlot(fragPosWorld, first + int(c));

  // blend into the NEXT cascade over a band before this cascade's split, to hide the boundary
  if (c < count) {
    float split = lightUbo.cascadeSplit[c];
    float band  = split * 0.15;                       // blend over the last 15% before the split
    if (shadowDistance > split - band) {
      float next = sampleSlot(fragPosWorld, first + int(c) + 1);
      float t = (shadowDistance - (split - band)) / band;  // 0 at band start, 1 at split
      shadow = mix(shadow, next, clamp(t, 0.0, 1.0));
    }
  }
  return shadow;
}

// Per-light shading: ambient + shadowed direct contribution
vec3 shadeLight(uint i, vec3 baseColor, vec4 fragPosWorld, vec3 normal, float shadowDistance, bool useShadows) {
  vec3 ambient;
  vec3 direct = illuminate(lightSSBO.lights[i], baseColor, fragPosWorld.xyz, normal, ambient);

  if (useShadows) { direct *= calculateShadow(fragPosWorld, lightSSBO.lights[i], shadowDistance); }
  return(ambient + direct);
}

// Returns the cascade index a fragment selects
vec3 cascadeTint(Light light, float viewDepth) {
  int first = int(light.cull[1]);
  if (first < 0) return vec3(0.3);                       // no shadow slot -> grey
  uint count = nCascades(light);
  uint c = 0u;
  if (count > 1u) { for (; c < count; ++c) { if (viewDepth <= lightUbo.cascadeSplit[c]) break; } }
  if (c == 0u) return vec3(1.0, 0.3, 0.3);               // near  = red
  if (c == 1u) return vec3(1.0, 1.0, 0.3);               // mid   = yellow
  if (c == 2u) return vec3(0.3, 1.0, 0.3);               // far   = green
  return vec3(0.0, 0.0, 0.0);                            // error = black
}

#endif // SAMPLERS_GLSL
