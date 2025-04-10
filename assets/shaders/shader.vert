// CaldaraD - Wavefront VERTEX SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 scene; // Scene Camera adjustment
    mat4 view;  // View matrix
    mat4 proj;  // Projection matrix
    mat4 ori;   // Screen orientation
} ubo;

// per Vertex attributes
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec2 inTexCoord;

// per Instance attributes
layout(location = 4) in uint Tid;
layout(location = 5) in mat4 instance;


layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec2 fragTexCoord;
layout(location = 3) out uint fragTid;

void main() {
  mat4 model = ubo.scene * instance;
  gl_Position = (ubo.ori * (ubo.proj * ubo.view * model)) * vec4(inPosition, 1.0);

  fragColor = inColor;
  fragNormal = inNormal;
  fragTexCoord = inTexCoord;
  fragTid = Tid;
}

