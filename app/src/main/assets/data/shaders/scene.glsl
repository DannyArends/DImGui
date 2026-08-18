// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef SCENE_GLSL
#define SCENE_GLSL

/// Uniform Buffer Objects
#define BINDING_SCENE_UBO          0
#define BINDING_LIGHT_UBO          1

/// Shader Storage Buffer Objects
#define BINDING_BONES_SSBO         2
#define BINDING_LIGHT_SSBO         3

/// Samplers/Images (defined in samplers.glsl)
//BINDING_TEXTURES = 4 & BINDING_SHADOWMAP = 5

/// Materials
#define BINDING_MATERIAL_SSBO      6

/// Lights
#define BINDING_CLUSTER_LIGHTS     7
#define BINDING_CLUSTER_HEADS      8
#define BINDING_CLUSTER_COUNTER    9

struct Light {
  vec4 position;      /// Position of the light; w==0: directional, w!=0: point/spot
  vec4 intensity;     /// Light intensity (color)
  vec4 direction;     /// Light direction
  vec4 properties;    /// [ambient, attenuation, angle, enabled]
  vec4 cull;          /// [radius, shadow map index (-1 = none), cosOuter, cosInner]
};

struct Bone {
  mat4 offset;        /// Bone offset
};

struct Material {
  int tid;   /// Diffuse texture ID
  int nid;   /// Normal map ID
  int oid;   /// Opacity texture ID
  int pad;
};

#define noMaterial Material(-1, -1, -1, 0)

struct LightIndex { uint light; uint next; };
struct Cursor { uint cursor; };
struct ClusterHead { uint head; };

/// Shader Storage Buffer Objects
layout (std430, set = 0, binding = BINDING_BONES_SSBO) readonly buffer BoneMatrices {
  Bone transforms[];
} boneSSBO;       // 2

layout (std430, set = 0, binding = BINDING_LIGHT_SSBO) readonly buffer LightMatrices {
  Light lights[];
} lightSSBO;      // 3

layout (std430, set = 0, binding = BINDING_MATERIAL_SSBO) readonly buffer MaterialBuffer {
  Material materials[];
} materialSSBO;   // 6

layout(std430, set=0, binding=BINDING_CLUSTER_LIGHTS) buffer ClusterLights {
  LightIndex indices[];
}; // 7

layout(std430, set=0, binding=BINDING_CLUSTER_HEADS) buffer ClusterHeads {
  ClusterHead head[];
}; // 8

layout(std430, set=0, binding=BINDING_CLUSTER_COUNTER) buffer ClusterCounter {
  Cursor cursor[];
};

/// UBO
layout(std140, binding = BINDING_SCENE_UBO) uniform UniformBufferObject {
  vec4 position;              /// Scene Camera Position
  mat4 viewProj;              /// View Projection Orientation matrix
  mat4 view;                  /// View matrix
  mat4 proj;                  /// Projection matrix
  mat4 ori;                   /// Screen orientation
  float shadowTexelSize;      /// Shadow texel size
  uint nlights;               /// Number of actual lights
  uint lightingMode;          /// Show shadows ?
  uint indexBufferLength;     /// Total entries in ClusterLights.indices[]
  vec4 clusterCfg;            /// [sliceScale, sliceBias, screenW, screenH]
} ubo;

layout(std140, set = 0, binding = BINDING_LIGHT_UBO) uniform LightSpaceMatrices {
  mat4 scene;
  vec4 cascadeSplit;              /// per-cascade view-depth splits (x,y,z used)
  mat4 slotVP[MAX_SHADOW_MAPS];   /// per-slot view-proj, shared by shadow + scene passes
  uint nlights;
} lightUbo;

#endif // SCENE_GLSL
