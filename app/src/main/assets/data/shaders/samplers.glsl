// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef SAMPLERS_GLSL
#define SAMPLERS_GLSL

#extension GL_EXT_nonuniform_qualifier : enable

#define SHADOW_SKIP 0.02
const float NORMAL_OFFSET = 0.12;   // world-space normal offset per cascade level (kills vertical-face peter-panning)

/// Samplers/Images
#define BINDING_TEXTURES          5
#define BINDING_SHADOWMAP         6
#define BINDING_SSAO             12

/// Samplers/Images
layout(binding = BINDING_TEXTURES) uniform sampler2D textureSampler[];
layout(binding = BINDING_SHADOWMAP) uniform sampler2DShadow shadowMap[];
layout(binding = BINDING_SSAO) uniform sampler2D ssaoSampler;

// Bump mapped normal
vec3 getBumpedNormal(vec3 cameraPos, vec3 fragPos, int fragNid, vec2 fragTexCoord, mat3 fragTBN){
  vec3 normalFromMap = texture(textureSampler[nonuniformEXT(fragNid)], fragTexCoord).rgb;
  return(normalize(fragTBN * normalize(normalFromMap * 2.0 - 1.0)));
}

// Sample one cascade slot; returns 1.0 (lit) if the fragment falls outside this slot's map.
float sampleSlot(vec4 fragPosWorld, int s, vec3 worldOffset) {
  vec4 position = lightUbo.slotVP[s] * vec4(fragPosWorld.xyz + worldOffset, 1.0);   // normal-offset receiver
  vec3 pC = position.xyz / position.w;
  pC.xy = pC.xy * 0.5 + 0.5;
  if (pC.x < 0.0 || pC.x > 1.0 || pC.y < 0.0 || pC.y > 1.0 || pC.z < 0.0 || pC.z > 1.0) return 1.0;
  return texture(shadowMap[nonuniformEXT(s)], pC);
}

// Number of interior cascade splits for this light (= cascade count − 1); 0 = point/spot (no cascades)
uint nCascadeSplits(Light light) { return (light.position.w == 0.0) ? uint(lightUbo.cascadeSplit.w) - 1u : 0u; }

// Sample shadow from cascade shadow map (and blend border)
float calculateShadow(vec4 fragPosWorld, Light light, vec3 normal, float shadowDistance, out int usedCascade) {
  usedCascade = -1;
  int first = int(light.cull[1]);
  if (first < 0) return 1.0;
  uint nSplits = nCascadeSplits(light);

  if (nSplits == 0u) return sampleSlot(fragPosWorld, first, vec3(0.0));

  uint c = 0u;
  for (; c < nSplits; ++c) { if (shadowDistance <= lightUbo.cascadeSplit[c]) break; }
  usedCascade = int(c);
  vec3 off = normal * (NORMAL_OFFSET * float(c + 1u));                 // ~texel-scaled push along the surface normal, grows with cascade
  float shadow = sampleSlot(fragPosWorld, first + int(c), off);

  if (c < nSplits) {
    float split = lightUbo.cascadeSplit[c];
    float band  = split * 0.08;
    if (shadowDistance > split - band) {
      float next = sampleSlot(fragPosWorld, first + int(c) + 1, normal * (NORMAL_OFFSET * float(c + 2u)));
      float t = (shadowDistance - (split - band)) / band;
      shadow = mix(shadow, next, clamp(t, 0.0, 1.0));
    }
  }
  return shadow;
}

// Per-light shading: ambient + shadowed direct contribution
vec3 shadeLight(uint i, vec3 baseColor, vec4 fragPosWorld, vec3 normal, float shadowDistance, bool useShadows) {
  vec3 ambient;
  vec3 direct = illuminate(lightSSBO.lights[i], baseColor, fragPosWorld.xyz, normal, ambient);

  int usedCascade;
  if (useShadows) { direct *= calculateShadow(fragPosWorld, lightSSBO.lights[i], normal, shadowDistance, usedCascade); }
  return(ambient + direct);
}

// Returns the cascade index a fragment selects
vec3 cascadeTint(Light light, float shadowDistance) {
  int first = int(light.cull[1]);
  if (first < 0) return vec3(0.3);                       // no shadow slot -> grey
  uint nSplits = nCascadeSplits(light);
  uint c = 0u;
  if (nSplits != 0u) { for (; c < nSplits; ++c) { if (shadowDistance <= lightUbo.cascadeSplit[c]) break; } }
  if (c == 0u) return vec3(1.0, 0.3, 0.3);               // near  = red
  if (c == 1u) return vec3(1.0, 1.0, 0.3);               // mid   = yellow
  if (c == 2u) return vec3(0.3, 1.0, 0.3);               // far   = green
  return vec3(0.0, 0.0, 0.0);                            // error = black
}

#endif // SAMPLERS_GLSL
