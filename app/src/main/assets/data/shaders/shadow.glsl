// DImGui - SHADOW SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "structures.glsl"
#include "functions.glsl"

layout(binding = BINDING_LIGHT_UBO) uniform LightSpaceMatrices {
  mat4 scene;           /// Scene matrix (currently, just and Identity matrix)
  uint clight;          /// Current light we're shadowing
  uint nlights;         /// Number of actual lights
} lightUbo;

// Per Vertex attributes
layout(location = 0) in vec3 inPosition;
layout(location = 1) in uvec4 inBones;
layout(location = 2) in vec4 inWeights;

// Per Instance attributes
layout(location = 3) in mat4 instance;

void main() {
  vec4 position = animate(vec4(inPosition, 1.0f), inBones, inWeights);
  mat4 model = lightUbo.scene * instance;
  vec4 worldPos = model * position;
  gl_Position = lightSSBO.lights[lightUbo.clight].lightProjView * worldPos;
  gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5; // Strange, depth values seem to be from -1.0f to 1.0f
}
