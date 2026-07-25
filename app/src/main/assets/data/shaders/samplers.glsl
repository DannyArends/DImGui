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

// Function to calculate the shadow factor
float calculateShadow(vec4 position, uint i) {
  int s = int(lightSSBO.lights[i].cull[1]);
  if (s < 0) return 1.0;
  vec3 pC = position.xyz / position.w;
  pC.xy = pC.xy * 0.5 + 0.5;

  if (pC.x < 0.0 || pC.x > 1.0 || pC.y < 0.0 || pC.y > 1.0 || pC.z < 0.0 || pC.z > 1.0) { return 1.0; }

  float shadowFactor = 0.0;
  vec2 t = vec2(ubo.shadowTexelSize);
  shadowFactor += texture(shadowMap[s], vec3(pC.xy + vec2(-0.5, -0.5) * t, pC.z));
  shadowFactor += texture(shadowMap[s], vec3(pC.xy + vec2( 0.5, -0.5) * t, pC.z));
  shadowFactor += texture(shadowMap[s], vec3(pC.xy + vec2(-0.5,  0.5) * t, pC.z));
  shadowFactor += texture(shadowMap[s], vec3(pC.xy + vec2( 0.5,  0.5) * t, pC.z));
  return shadowFactor * 0.25;
}

// CSM: pick the cascade whose split covers viewDepth and sample it. cascade 0 == light 0 (sun).
// dbgCascade returns which cascade was used (for the debug tint); remove once verified.
float calculateShadowCSM(vec4 fragPosWorld, float viewDepth, out int dbgCascade) {
  uint base  = uint(ubo.cascade.x);
  uint count = uint(ubo.cascade.y);
  for (uint c = 0u; c < count; ++c) {
    uint li = (c == 0u) ? 0u : base + (c - 1u);
    if (viewDepth <= lightSSBO.lights[li].cull.z || c == count - 1u) {
      dbgCascade = int(c);
      return calculateShadow(lightSSBO.lights[li].lightProjView * fragPosWorld, li);
    }
  }
  dbgCascade = -1; return 1.0;
}

// Per-light shading: ambient + shadowed direct contribution
vec3 shadeLight(uint idx, vec3 baseColor, vec4 fragPosWorld, vec3 normal, bool useShadows) {
  vec3 ambient;
  vec3 direct = illuminate(lightSSBO.lights[idx], baseColor, fragPosWorld.xyz, normal, ambient);
  if (useShadows && max(direct.r, max(direct.g, direct.b)) > SHADOW_SKIP) {
    direct *= calculateShadow(lightSSBO.lights[idx].lightProjView * fragPosWorld, idx);
  }
  return(ambient + direct);
}

#endif // SAMPLERS_GLSL
