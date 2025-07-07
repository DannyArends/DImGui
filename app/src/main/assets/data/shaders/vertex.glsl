// DImGui - VERTEX SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "structures.glsl"
#include "functions.glsl"

layout(std140, binding = BINDING_SCENE_UBO) uniform UniformBufferObject {
    vec4 position;    // Scene Camera Position
    mat4 scene;       // Scene Camera adjustment
    mat4 view;        // View matrix
    mat4 proj;        // Projection matrix
    mat4 ori;         // Screen orientation
    Light[4] lights;  // Scene lights
    uint nlights;     // Number of actual lights
} ubo;

// Per Vertex attributes
layout(location = 0) in vec3 inPosition;          /// Vertex position
layout(location = 1) in vec4 inColor;             /// TODO: get from materialSSB0.materials[] with meshSSBO.meshes[i].material
layout(location = 2) in vec3 inNormal;            /// Normal
layout(location = 3) in vec2 inTexCoord;          /// Texture coordinate
layout(location = 4) in vec3 inTangent;           /// Tangent vector
layout(location = 5) in uvec4 inBones;            /// assimp: BoneIDs
layout(location = 6) in vec4 inWeights;           /// assimp: BoneWeights

// Per Instance attributes
layout(location = 7) in uvec3 meshdef;            /// Mesh start + stop
layout(location = 8) in mat4 instance;            /// Instance matrix
layout(location = 12) in mat4 nMatrix;            /// Normal matrix

// Output to Fragment shader
layout(location = 0) out vec4 fragPosWorld;       /// Fragment world position
layout(location = 1) out vec4 fragColor;          /// Fragment color
layout(location = 2) out vec3 fragNormal;         /// Fragment normal
layout(location = 3) out vec2 fragTexCoord;       /// Texture coordinate
layout(location = 4) flat out int fragTid;        /// Texture ID
layout(location = 5) flat out int fragNid;        /// Normal Map ID
layout(location = 6) out mat3 fragTBN;            /// Tangent, Bitangent, Normal matrix

void main() {
  /// Compute bone effects on vertex
  vec4 position = animate(vec4(inPosition, 1.0f), inBones, inWeights);

  /// Compute our model matrix
  mat4 model = ubo.scene * instance;

  /// Calculate the world-space normal, bitangent, tangent, and normal matrix
  vec3 N = normalize(mat3(instance) * inNormal);
  vec3 T = normalize(mat3(instance) * inTangent);
  vec3 B = normalize(cross(N, T));

  /// World position & point size
  gl_Position = (ubo.ori * (ubo.proj * ubo.view * model)) * position;
  gl_PointSize = 2.0f;

  /// Transfer data to fragment shader
  fragPosWorld = (model * position);
  fragColor = inColor;
  fragNormal = normalize(vec3(mat3(nMatrix) * inNormal));
  fragTexCoord = inTexCoord;
  uint mesh = meshdef[0];
  if(meshdef[0] != meshdef[1]) {
    for (uint i = meshdef[0]; i < meshdef[1]; i++) {
      if (meshSSBO.meshes[i].vertices[0] <= gl_VertexIndex && gl_VertexIndex < meshSSBO.meshes[i].vertices[1]) {
        mesh = i;
        break;
      }
    }
  }
  fragTid = meshSSBO.meshes[mesh].tid;
  fragNid = meshSSBO.meshes[mesh].nid;
  fragTBN = mat3(T, B, N); 
}
