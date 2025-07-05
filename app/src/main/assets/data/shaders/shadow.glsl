// DImGui - SHADOW SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

struct Bone {
  mat4 offset;
};

layout (std140, binding = 1) readonly buffer BoneMatrices {
    Bone transforms[];
} boneSSBO;


layout(set = 0, binding = 0) uniform LightSpaceMatrices {
  mat4 lightProjView; // Combined light's projection * light's view matrix
  mat4 scene;
} lightUbo;

// Per Vertex attributes
layout(location = 0) in vec3 inPosition;
layout(location = 1) in uvec4 inBones;
layout(location = 2) in vec4 inWeights;

// Per Instance attributes
layout(location = 3) in mat4 instance;

void main() {
  bool hasbone = false;
  vec4 bonepos = vec4(0.0f, 0.0f, 0.0f, 0.0f);
  for (int i = 0; i < 4; i++) {
    float weight = inWeights[i];
    if(weight > 0.0f) {
      uint boneID = inBones[i];
      mat4 boneTransform = boneSSBO.transforms[boneID].offset;
      bonepos += (boneTransform * vec4(inPosition, 1.0f)) * weight;
      hasbone = true;
    }
  }
  vec4 finalPosition = vec4(inPosition, 1.0f);
  if(hasbone){ finalPosition = bonepos; }

  mat4 modelMatrix = lightUbo.scene * instance;
  vec4 worldPos = modelMatrix * finalPosition;
  gl_Position = lightUbo.lightProjView * worldPos;
  gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5; // Strange, depth values seem to be from -1.0f to 1.0f
}
