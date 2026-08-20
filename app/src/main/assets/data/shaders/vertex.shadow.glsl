// DImGui - SHADOW SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460
#extension GL_EXT_nonuniform_qualifier : enable

#include "functions.glsl"
#include "scene.glsl"

layout(push_constant) uniform PushConstants {
    uint clight;
} pc;

// Per Vertex attributes
layout(location = 0) in vec3 inPosition;              /// Vertex Position
layout(location = 1) in uvec4 inBones;                /// assimp: BoneIDs
layout(location = 2) in vec4 inWeights;               /// assimp: BoneWeights

// Per Instance attributes
layout(location = 3) in vec4 instanceAux;             /// [staticBase, boneBase, unused, unused]
layout(location = 4) in mat4 instance;                /// Instance matrix

void main() {
  vec4 position = staticSSBO.transforms[uint(instanceAux[0])].offset * vec4(inPosition, 1.0);
  if(ANIMATED) position = animate(position, inBones, inWeights, uint(instanceAux[1]));
  gl_Position = lightUbo.slotVP[pc.clight] * ((lightUbo.scene * instance) * position);
}
