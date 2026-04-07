// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef STRUCTURES_GLSL
#define STRUCTURES_GLSL

/// Uniform Buffer Objects
#define BINDING_SCENE_UBO         0
#define BINDING_LIGHT_UBO         1

/// Shader Storage Buffer Objects
#define BINDING_BONES_SSBO        2
#define BINDING_MESH_SSBO         3
#define BINDING_LIGHT_SSBO        4

/// Samplers/Images
#define BINDING_TEXTURES          5
#define BINDING_SHADOWMAP         6

struct Light {
  mat4 lightProjView; /// Combined light's projection * light's view matrix
  vec4 position;      /// Position of the light
  vec4 intensity;     /// Light intensity (color)
  vec4 direction;     /// Light direction
  vec4 properties;    /// [ambient, attenuation, angle]
};

struct Bone {
  mat4 offset;        /// Bone offset
};

struct Mesh {
  uvec2 vertices;     /// Start & End vertex
  int mid;            /// Material ID
  int tid;            /// Texture ID
  int nid;            /// BumpMap ID
  int oid;            /// OPACITY ID
};

/// Shader Storage Buffer Objects
layout (std430, set = 0, binding = BINDING_MESH_SSBO) readonly buffer MeshMatrices {
    Mesh meshes[];
} meshSSBO;

layout (std430, set = 0, binding = BINDING_LIGHT_SSBO) readonly buffer LightMatrices {
    Light lights[];
} lightSSBO;

layout (std430, set = 0, binding = BINDING_BONES_SSBO) readonly buffer BoneMatrices {
    Bone transforms[];
} boneSSBO;

/// UBO
layout(std140, binding = BINDING_SCENE_UBO) uniform UniformBufferObject {
  vec4 position;              /// Scene Camera Position
  mat4 scene;                 /// Scene Camera adjustment
  mat4 view;                  /// View matrix
  mat4 proj;                  /// Projection matrix
  mat4 ori;                   /// Screen orientation
  uint nlights;               /// Number of actual lights
  uint lightingMode;          /// Show shadows ?
} ubo;

/// Samplers/Images
layout(binding = BINDING_TEXTURES) uniform sampler2D textureSampler[];
layout(binding = BINDING_SHADOWMAP) uniform sampler2DShadow shadowMap[];

#endif // STRUCTURES_GLSL
