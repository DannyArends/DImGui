// DImGui - VERTEX SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "structures.glsl"
#include "functions.glsl"

// Per Vertex attributes
layout(location = 0) in vec3  inPosition;             /// Vertex Position
layout(location = 1) in vec4  inColor;                /// Vertex Color
layout(location = 2) in vec3  inNormal;               /// Normal
layout(location = 3) in vec2  inTexCoord;             /// Texture coordinate
layout(location = 4) in vec4  inTangent;              /// Tangent xyz + handedness w
layout(location = 5) in uvec4 inBones;                /// assimp: BoneIDs
layout(location = 6) in vec4  inWeights;              /// assimp: BoneWeights

// Per Instance attributes
layout(location = 7) in uvec2 meshdef;                /// Mesh [start, stop, material, texure override]
layout(location = 8) in int   material;               /// per-Instance material
layout(location = 9) in vec4  instanceColor;          /// per-Instance Color
layout(location = 10) in vec4 instanceTangent;        /// Per-instance Tangent xyz + handedness w
layout(location = 11) in mat4 instance;               /// Instance matrix

// Output to Fragment shader
layout(location = 0) out vec4 fragPosWorld;           /// Fragment world position
layout(location = 1) out vec4 fragColor;              /// Fragment color
layout(location = 2) out vec3 fragNormal;             /// Fragment normal
layout(location = 3) out vec2 fragTexCoord;           /// Texture coordinate
layout(location = 4) flat out ivec2 fragInstance;     /// [meshID, material override]
layout(location = 5) out mat3 fragTBN;                /// Tangent, Bitangent, Normal matrix

// Compile time constants
layout(constant_id = 1) const bool INSTANCED = true;  /// INSTANCED rendering (uses per instance attributes over-writes)

void main() {
  /// Compute bone effects on vertex
  vec4 position = animate(vec4(inPosition, 1.0f), inBones, inWeights);
  mat3 normalMatrix = transpose(inverse(mat3(instance)));

  /// Compute our model matrix
  mat4 model = ubo.scene * instance;

  /// Calculate the world-space normal, bitangent, tangent, and normal matrix
  vec3 N = normalize(mat3(instance) * inNormal);
  vec3 T = normalize(mat3(instance) * (INSTANCED ? instanceTangent.xyz : inTangent.xyz));
  vec3 B = cross(N, T) * (INSTANCED ? instanceTangent.w : inTangent.w);

  /// World position & point size
  gl_Position = (ubo.ori * (ubo.proj * ubo.view * model)) * position;
  gl_PointSize = 2.0f;

  /// Transfer data to fragment shader
  fragPosWorld = (model * position);
  fragColor = INSTANCED ? instanceColor : inColor;
  fragNormal = normalize(normalMatrix * inNormal);
  fragTexCoord = inTexCoord;
  uint meshID = meshdef[0];
  if(meshdef[0] != meshdef[1]) {
    for (; meshID < meshdef[1]; meshID++) {
      if (meshSSBO.meshes[meshID].vertices[0] <= gl_VertexIndex && gl_VertexIndex < meshSSBO.meshes[meshID].vertices[1]) break;
    }
  }
  fragInstance = ivec2(meshID, material);
  fragTBN = mat3(T, B, N); 
}

