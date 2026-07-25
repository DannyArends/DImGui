// DImGui - VERTEX SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "functions.glsl"

// Per Vertex input attributes
layout(location = 0) in vec3  inPosition;             /// Vertex Position
layout(location = 1) in vec4  inColor;                /// Vertex Color
layout(location = 2) in vec3  inNormal;               /// Normal
layout(location = 3) in vec2  inTexCoord;             /// Texture coordinate
layout(location = 4) in vec4  inTangent;              /// Tangent xyz + handedness w
layout(location = 5) in uvec4 inBones;                /// assimp: BoneIDs
layout(location = 6) in vec4  inWeights;              /// assimp: BoneWeights

// Per Instance input attributes
layout(location = 7) in ivec4 meshdef;                /// Mesh [start, stop, material, unused]
layout(location = 8) in vec4  instanceColor;          /// per-Instance Color
layout(location = 9) in vec4  instanceUV;             /// Per-instance UV remap [offsetX, offsetY, scaleX, scaleY]
layout(location = 10) in vec4 instanceNormal;         /// baked world normal (instanced faces)
layout(location = 11) in vec4 instanceTangent;        /// baked world tangent + handedness
layout(location = 12) in mat4 instance;               /// Instance matrix

// Output to Fragment shader
layout(location = 0) out vec4 fragPosWorld;           /// Fragment world position
layout(location = 1) out vec4 fragColor;              /// Fragment color
layout(location = 2) out vec3 fragNormal;             /// Fragment normal
layout(location = 3) out vec2 fragTexCoord;           /// Texture coordinate
layout(location = 4) flat out ivec2 fragInstance;     /// [meshID, material override]
layout(location = 5) out vec3 fragViewPos;            /// View-space position (froxel lookup)
layout(location = 6) out mat3 fragTBN;                /// Tangent, Bitangent, Normal matrix

void main() {
  /// Compute bone effects on vertex
  vec4 position = ANIMATED ? animate(vec4(inPosition, 1.0f), inBones, inWeights) : vec4(inPosition, 1.0f);

  /// Compute our model matrix
  vec4 worldPos = instance * position;

  /// World position & point size
  gl_Position = ubo.viewProj * worldPos;
  gl_PointSize = 2.0f;

  fragColor = INSTANCED ? instanceColor : inColor;
  fragTexCoord = instanceUV.xy + inTexCoord * instanceUV.zw;
  uint meshID = meshdef[0];
  if(meshdef[0] != meshdef[1]) {
    for (; meshID < meshdef[1]; meshID++) {
      if (meshSSBO.meshes[meshID].vertices[0] <= gl_VertexIndex && gl_VertexIndex < meshSSBO.meshes[meshID].vertices[1]) break;
    }
  }
  fragInstance = ivec2(meshID, meshdef[2]);

  if(!DEPTH_PASS) { /// Full lighting varyings only needed in the scene pass
    fragPosWorld = worldPos;
    fragViewPos = (ubo.view * worldPos).xyz;
    bool hasBakedNormal = (meshdef[3] != 0);
    vec3 N = hasBakedNormal ? instanceNormal.xyz : normalize(mat3(instance) * inNormal);
    fragNormal = N;
    if(NORMAL_MAPPED) {
      vec3 T = hasBakedNormal ? instanceTangent.xyz : normalize(mat3(instance) * inTangent.xyz);
      vec3 B = normalize(cross(N, T)) * (hasBakedNormal ? instanceTangent.w : inTangent.w);
      fragTBN = mat3(T, B, N);
    }
  }
}

