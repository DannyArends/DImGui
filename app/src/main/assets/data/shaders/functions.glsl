// DImGui - Function Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef FUNCTIONS_GLSL
#define FUNCTIONS_GLSL

#include "scene.glsl"

// Function to calculate vector position after animation
vec4 animate(vec4 inPos, uvec4 inBones, vec4 inWeights) {
  bool hasbone = false;
  vec4 bonepos = vec4(0.0f, 0.0f, 0.0f, 0.0f);
  for (int i = 0; i < 4; i++) {
    float weight = inWeights[i];
    if(weight > 0.0f) {
      uint boneID = inBones[i];
      mat4 boneTransform = boneSSBO.transforms[boneID].offset;
      bonepos += (boneTransform * inPos) * weight;
      hasbone = true;
    }
  }
  vec4 finalPosition = inPos;
  if(hasbone){ finalPosition = bonepos; }
  return(finalPosition);
}

// Our illumination function
vec3 illuminate(Light light, vec3 baseColor, vec3 position, vec3 normal, vec3 cameraPos) {
  if (light.properties.w == 0.0) return vec3(0.0);
  float attenuation = 1.0;
  vec3 s;
  if (light.position.w == 0.0) {                          // Directional lighting
    s = normalize( light.position.xyz );
  } else {                                                // Point lighting
    s = normalize( light.position.xyz - position );
    float l = length( light.position.xyz - position );
    if (l > light.cull.x) return vec3(0.0);   // outside cull radius
    attenuation = 1.0 / (light.properties[1] + l * l);

    // Cone lighting
    float cosOuter = cos(radians(light.properties[2]));
    float cosInner = cos(radians(light.properties[2] / 2.0f));
    float cosAngle = dot(-s, normalize(light.direction.xyz));
    float coneFactor = smoothstep(cosOuter, cosInner, cosAngle);

    attenuation *= coneFactor;
  }
  float sDotN = max( dot( s, normal ), 0.0 );

  vec3 ambientCol = light.intensity.rgb * baseColor * light.properties[0];
  vec3 diffuseCol = light.intensity.rgb * baseColor * sDotN;
  return ambientCol + attenuation * diffuseCol;
}

vec3 applyFog(vec3 color, vec3 fragPos, vec3 cameraPos, float fogStart, float fogEnd, vec3 fogColor) {
  vec2 horizDist = fragPos.xz - cameraPos.xz;  // XZ only, ignore height
  float dist = length(horizDist);
  float fogFactor = clamp((fogEnd - dist) / (fogEnd - fogStart), 0.0, 1.0);
  return mix(fogColor, color, fogFactor);
}

uint froxelIndex(vec2 fragCoordXY, float viewDepth) {
  vec2 tile = ubo.clusterCfg.zw / vec2(ubo.grid.xy);
  uint gx = uint(clamp(fragCoordXY.x / tile.x, 0.0, float(ubo.grid.x - 1u)));
  uint gy = uint(clamp(fragCoordXY.y / tile.y, 0.0, float(ubo.grid.y - 1u)));
  int zs = int(floor(log2(viewDepth) * ubo.clusterCfg.x + ubo.clusterCfg.y));
  uint gz = uint(clamp(zs, 0, int(ubo.grid.z) - 1));
  return (gz * ubo.grid.y + gy) * ubo.grid.x + gx;
}

// returns NDC min/max for one axis; p = projection scale (P00 or P11), cz = -depth
// cc = center coord on this axis (cV.x or cV.y), cz = cV.z (negative)
vec2 projectAxis(float cc, float cz, float r, float p, float depth) {
  float t  = sqrt(cc*cc + cz*cz - r*r);
  float a  = r / sqrt(cc*cc + cz*cz);
  float s  = sqrt(1.0 - a*a);

  vec2 d1 = vec2( s*cc - a*cz,  a*cc + s*cz);
  vec2 d2 = vec2( s*cc + a*cz, -a*cc + s*cz);

  float n1 = p * d1.x / -d1.y;                  // NDC = p * x / -z
  float n2 = p * d2.x / -d2.y;
  return vec2(min(n1, n2), max(n1, n2));
}

#endif // FUNCTIONS_GLSL
