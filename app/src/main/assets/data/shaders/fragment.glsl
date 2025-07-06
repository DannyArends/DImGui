// DImGui - FRAGMENT SHADER
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

layout(location = 0) in vec3 fragPosWorld;
layout(location = 1) in vec4 fragPosLightSpace;
layout(location = 2) in vec4 fragColor;
layout(location = 3) in vec3 fragNormal;
layout(location = 4) in vec2 fragTexCoord;
layout(location = 5) flat in int fragTid;
layout(location = 6) flat in int fragNid;
layout(location = 7) in mat3 fragTBN;

layout(location = 0) out vec4 outColor;

void main() {
  // Sample the base color
  vec3 baseColor = fragColor.rgb;
  if(fragTid >= 0){
    vec4 texColor = texture(texureSampler[fragTid], fragTexCoord).rgba;
    if(texColor.a < 0.2f) discard;
    baseColor = fragColor.rgb * texColor.rgb;
  }

  // Bump map
  vec3 adjustment = vec3(1.0f);
  if(fragNid >= 0) {
    adjustment = calculateBump(ubo.lights[0], ubo.position.xyz, fragPosWorld, fragNid, fragTexCoord, fragTBN);
  }

  // Compute shadow factor
  float shadowFactor = calculateShadow(fragPosLightSpace);
  outColor = vec4(baseColor * adjustment * shadowFactor, 1.0);
}
