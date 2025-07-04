// DImGui - SHADOW SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

layout(set = 0, binding = 0) uniform LightSpaceMatrices {
  mat4 lightProjView; // Combined light's projection * light's view matrix
  mat4 scene;
} lightUbo;

// Per Vertex attributes
layout(location = 0) in vec3 inPosition;

// Per Instance attributes
layout(location = 1) in mat4 instance;

void main() {
  mat4 modelMatrix = lightUbo.scene * instance;
  vec4 worldPos = modelMatrix * vec4(inPosition, 1.0);
  gl_Position = lightUbo.lightProjView * worldPos;
}
