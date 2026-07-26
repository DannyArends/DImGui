// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef SAMPLERS_GLSL
#define SAMPLERS_GLSL

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
  vec3 normalFromMap = texture(textureSampler[fragNid], fragTexCoord).rgb;
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
  vec2 t = vec2(ubo.shadowTexelSize);
  float sf = 0.0;
  sf += texture(shadowMap[s], vec3(pC.xy + vec2(-0.5, -0.5) * t, pC.z));
  sf += texture(shadowMap[s], vec3(pC.xy + vec2( 0.5, -0.5) * t, pC.z));
  sf += texture(shadowMap[s], vec3(pC.xy + vec2(-0.5,  0.5) * t, pC.z));
  sf += texture(shadowMap[s], vec3(pC.xy + vec2( 0.5,  0.5) * t, pC.z));
  return sf * 0.25;
}

float calculateShadow(vec4 fragPosWorld, uint i, float viewDepth) {
  int first = int(lightSSBO.lights[i].cull[1]);
  if (first < 0) return 1.0;
  uint count = (lightSSBO.lights[i].position.w == 0.0) ? uint(lightSSBO.lights[i].cull[2]) : 1u;

  // single-slot (point/spot): no cascade blend
  if (count <= 1u) return sampleSlot(fragPosWorld, first);

  // pick cascade c by distance
  uint c = 0u;
  for (; c < count - 1u; ++c) { if (viewDepth <= lightUbo.cascadeSplit[c]) break; }
  float shadow = sampleSlot(fragPosWorld, first + int(c));

  // blend into the NEXT cascade over a band before this cascade's split, to hide the boundary
  if (c < count - 1u) {
    float split = lightUbo.cascadeSplit[c];
    float band  = split * 0.15;                       // blend over the last 15% before the split
    if (viewDepth > split - band) {
      float next = sampleSlot(fragPosWorld, first + int(c) + 1);
      float t = (viewDepth - (split - band)) / band;  // 0 at band start, 1 at split
      shadow = mix(shadow, next, clamp(t, 0.0, 1.0));
    }
  }
  return shadow;
}

// Per-light shading: ambient + shadowed direct contribution
vec3 shadeLight(uint idx, vec3 baseColor, vec4 fragPosWorld, vec3 normal, float viewDepth, bool useShadows) {
  vec3 ambient;
  vec3 direct = illuminate(lightSSBO.lights[idx], baseColor, fragPosWorld.xyz, normal, ambient);

  if (useShadows) { direct *= calculateShadow(fragPosWorld, idx, viewDepth); }
  return(ambient + direct);
}

// DEBUG: returns the cascade index a fragment selects (mirrors calculateShadow's selection)
vec3 cascadeTint(uint i, float viewDepth) {
  int first = int(lightSSBO.lights[i].cull[1]);
  if (first < 0) return vec3(0.3);                       // no shadow slot -> grey
  uint count = (lightSSBO.lights[i].position.w == 0.0) ? uint(lightSSBO.lights[i].cull[2]) : 1u;
  uint c = 0u;
  if (count > 1u) { for (; c < count - 1u; ++c) { if (viewDepth <= lightUbo.cascadeSplit[c]) break; } }
  if (c == 0u) return vec3(1.0, 0.3, 0.3);               // near  = red
  if (c == 1u) return vec3(0.3, 1.0, 0.3);               // mid   = green
  if (c == 2u) return vec3(0.3, 0.3, 1.0);               // far   = blue
  return vec3(1.0, 1.0, 0.3);                            // extra = yellow
}

#endif // SAMPLERS_GLSL
