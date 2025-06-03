// DImGui - POINT SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

layout(binding = 0) uniform UniformBufferObject {
    mat4 scene;       // Scene Camera adjustment
    mat4 view;        // View matrix
    mat4 proj;        // Projection matrix
    mat4 ori;         // Screen orientation
} ubo;

// Per Vertex attributes
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;

// Per Instance attributes
layout(location = 5) in mat4 instance;

// Output to Fragment shader
layout(location = 0) out vec4 fragColor;

void main() {
  mat4 model = ubo.scene * instance;
  gl_Position = (ubo.ori * (ubo.proj * ubo.view * model)) * vec4(inPosition, 1.0);
  gl_PointSize = 2.0f;

  fragColor = vec4(inColor, 1.0f);
}
