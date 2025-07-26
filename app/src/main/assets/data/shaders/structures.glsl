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

#endif // STRUCTURES_GLSL
