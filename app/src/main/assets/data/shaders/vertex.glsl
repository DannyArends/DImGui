// DImGui - VERTEX SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "functions.glsl"

// Per Vertex input attributes
layout(location = 0) in vec3  inPosition;             /// Vertex Position
layout(location = 1) in vec3  inNormal;               /// Normal
layout(location = 2) in vec3  inDef;                  /// [material, color, alpha]
layout(location = 3) in vec2  inTexCoord;             /// Texture coordinate
layout(location = 4) in vec4  inTangent;              /// Tangent xyz + handedness w
layout(location = 5) in uvec4 inBones;                /// assimp: BoneIDs
layout(location = 6) in vec4  inWeights;              /// assimp: BoneWeights

// Per Instance input attributes
layout(location = 7) in vec4 instanceDef;             /// [material, color, alpha, boneBase]
layout(location = 8) in vec4 instanceAux;             /// [nonBoneIdx,unused,unused,unused]
layout(location = 9) in vec4 instanceUV;              /// Per-instance UV remap [offsetX, offsetY, scaleX, scaleY]
layout(location = 10) in vec4 instanceNormal;         /// baked world normal (instanced faces)
layout(location = 11) in vec4 instanceTangent;        /// baked world tangent + handedness
layout(location = 12) in mat4 instance;               /// Instance matrix

// Output to Fragment shader
layout(location = 0) out vec4 fragPosWorld;           /// Fragment world position
layout(location = 1) out vec4 fragColor;              /// Resolved rgb + alpha (interpolated)
layout(location = 2) out vec3 fragNormal;             /// Fragment normal
layout(location = 3) out vec2 fragTexCoord;           /// Texture coordinate
layout(location = 4) flat out int fragMaterial;       /// Resolved Material
layout(location = 5) out vec3 fragViewPos;            /// View-space position (froxel lookup)
layout(location = 6) out mat3 fragTBN;                /// Tangent, Bitangent, Normal matrix

void main() {
  vec4 position = staticSSBO.transforms[uint(instanceAux[0])].offset * vec4(inPosition, 1.0);

  /// Compute bone effects on vertex
  if(ANIMATED) position = animate(position, inBones, inWeights, uint(instanceDef[3]));

  /// Compute our model matrix
  vec4 worldPos = instance * position;

  /// World position & point size
  gl_Position = ubo.viewProj * worldPos;
  gl_PointSize = 2.0f;

  /// Fragment texture
  fragTexCoord = instanceUV.xy + inTexCoord * instanceUV.zw;

  // Fragment color
  int colorIdx = (instanceDef[1] >= 0.0) ? int(instanceDef[1]) : int(inDef[1]);
  float alpha = (instanceDef[2] >= 0.0) ? instanceDef[2] : inDef[2];
  fragColor = vec4((colorIdx >= 0) ? colorSSBO.colors[colorIdx].rgb.rgb : vec3(1.0), alpha);

  /// [baked material id, per-instance override]
  fragMaterial = (instanceDef[0] >= 0.0) ? int(instanceDef[0]) : int(inDef[0]);

  if(!DEPTH_PASS) { /// Full lighting varyings only needed in the scene pass
    fragPosWorld = worldPos;
    fragViewPos = (ubo.view * worldPos).xyz;
    bool hasBakedNormal = (instanceNormal.w != 0.0);
    vec3 nModel = ANIMATED ? animate(vec4(inNormal, 0.0f), inBones, inWeights, uint(instanceDef[3])).xyz : inNormal;
    vec3 N = hasBakedNormal ? instanceNormal.xyz : normalize(mat3(instance) * nModel);
    fragNormal = N;
    if(NORMAL_MAPPED) {
      vec3 tModel = ANIMATED ? animate(vec4(inTangent.xyz, 0.0f), inBones, inWeights, uint(instanceDef[3])).xyz : inTangent.xyz;
      vec3 T = hasBakedNormal ? instanceTangent.xyz : normalize(mat3(instance) * tModel);
      vec3 B = normalize(cross(N, T)) * (hasBakedNormal ? instanceTangent.w : inTangent.w);
      fragTBN = mat3(T, B, N);
    }
  }
}

