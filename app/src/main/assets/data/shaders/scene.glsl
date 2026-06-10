// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef SCENE_GLSL
#define SCENE_GLSL

// Compile time constants
layout(constant_id = 0) const int TOPOLOGY = 3;
layout(constant_id = 1) const bool ALPHA_TEST = true;
layout(constant_id = 2) const bool INSTANCED = true;

/// Uniform Buffer Objects
#define BINDING_SCENE_UBO          0
#define BINDING_LIGHT_UBO          1

/// Shader Storage Buffer Objects
#define BINDING_BONES_SSBO         2
#define BINDING_MESH_SSBO          3
#define BINDING_LIGHT_SSBO         4

/// Samplers/Images (defined in samplers.glsl)
//BINDING_TEXTURES = 5 & BINDING_SHADOWMAP = 6

/// Materials
#define BINDING_MATERIAL_SSBO      7

/// Lights
#define BINDING_CLUSTER_LIGHTS     8
#define BINDING_CLUSTER_RANGE      9
#define BINDING_CLUSTER_COUNTER   10

struct Light {
  mat4 lightProjView; /// Combined light's projection * light's view matrix
  vec4 position;      /// Position of the light
  vec4 intensity;     /// Light intensity (color)
  vec4 direction;     /// Light direction
  vec4 properties;    /// [ambient, attenuation, angle, enabled]
  vec4 cull;          /// [radius, shadowSlot, reserved, reserved]
};

struct Bone {
  mat4 offset;        /// Bone offset
};

struct Mesh {
  uvec2 vertices;     /// Start & End vertex
  int mid;            /// Material ID
  int mat;            /// assimp-local material index
};

struct Material {
  int tid;   /// Diffuse texture ID
  int nid;   /// Normal map ID
  int oid;   /// Opacity texture ID
  int pad;
};

struct LightIndex { uint light; };
struct Cursor { uint cursor; };
struct ClusterRange { uint offset; uint count; };

/// Shader Storage Buffer Objects
layout (std430, set = 0, binding = BINDING_BONES_SSBO) readonly buffer BoneMatrices {
  Bone transforms[];
} boneSSBO;       // 2

layout (std430, set = 0, binding = BINDING_MESH_SSBO) readonly buffer MeshMatrices {
  Mesh meshes[];
} meshSSBO;       // 3

layout (std430, set = 0, binding = BINDING_LIGHT_SSBO) readonly buffer LightMatrices {
  Light lights[];
} lightSSBO;      // 4

layout (std430, set = 0, binding = BINDING_MATERIAL_SSBO) readonly buffer MaterialBuffer {
  Material materials[];
} materialSSBO;   // 7

layout(std430, set=0, binding=BINDING_CLUSTER_LIGHTS) buffer ClusterLights {
  LightIndex indices[];
}; // 8

layout(std430, set=0, binding=BINDING_CLUSTER_RANGE) buffer ClusterRanges {
  ClusterRange ranges[];
}; // 9

layout(std430, set=0, binding=BINDING_CLUSTER_COUNTER) buffer ClusterCounter {
  Cursor cursor[];
};

/// UBO
layout(std140, binding = BINDING_SCENE_UBO) uniform UniformBufferObject {
  vec4 position;              /// Scene Camera Position
  mat4 scene;                 /// Scene Camera adjustment
  mat4 view;                  /// View matrix
  mat4 proj;                  /// Projection matrix
  mat4 invProj;               /// Inverse projection matrix
  mat4 ori;                   /// Screen orientation
  float shadowTexelSize;      /// Shadow texel size
  uint nlights;               /// Number of actual lights
  uint lightingMode;          /// Show shadows ?
  uint indexBufferLength;     /// Total entries in ClusterLights.indices[]
  uvec4 grid;                 /// [gridX, gridY, gridZ, unused]
  vec4 clusterCfg;            /// [sliceScale, sliceBias, screenW, screenH]
} ubo;

#endif // SCENE_GLSL
