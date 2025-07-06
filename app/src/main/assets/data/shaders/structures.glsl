// DImGui - Structure Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef STRUCTURES_GLSL
#define STRUCTURES_GLSL

// Uniform Buffer Objects
#define BINDING_SCENE_UBO         0
#define BINDING_LIGHT_UBO         1

// Shader Storage Buffer Objects
#define BINDING_BONES_SSBO        2
#define BINDING_MESH_SSBO         3
#define BINDING_MATERIALS_SSBO    4

// Samplers/Images
#define BINDING_TEXTURES          5
#define BINDING_SHADOWMAP         6

struct Light {
  vec4 position;
  vec4 intensity;
  vec4 direction;
  vec4 properties;    // [ambient, attenuation, angle]
};

struct Bone {
  mat4 offset;
};

struct Material {
  vec4 color;
  uint base;
  uint normal;
};

struct Mesh {
  uvec2 vertices;     // Start & End vertex
  uint material;      // Material ID
};

#endif // STRUCTURES_GLSL