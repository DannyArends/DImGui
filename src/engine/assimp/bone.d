/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.array : array;
import std.algorithm : sort;
import std.string : lastIndexOf;

import matrix : Matrix, inverse, position, transpose;
import animation : Node, calculateGlobalTransform;
import assimp : name, toMatrix;

struct Bone {
  Matrix offset;          /// Inverse bind pose matrix
  uint index;             /// Bone index

  @property float[3] bindPosition() { return offset.inverse().position(); }
}

float[uint][string] loadBones(aiMesh* mesh, ref Bone[string] globalBones) {
  float[uint][string] weights;
  for (uint b = 0; b < mesh.mNumBones; b++) {
    auto aiBone = mesh.mBones[b];
    if(aiBone.mNumWeights == 0) continue;
    string name = aiBone.name();
    if(!(name in globalBones)){
      globalBones[name] = Bone();
      globalBones[name].offset = toMatrix(aiBone.mOffsetMatrix);
      globalBones[name].index = cast(uint)(globalBones.length-1);
    }
    SDL_Log(toStringz(format("%s.bone: %d -> %d", name, globalBones[name].index, aiBone.mNumWeights)));
    for (uint w = 0; w < aiBone.mNumWeights; w++) {
      auto aiWeight = aiBone.mWeights[w];
      weights[name][aiWeight.mVertexId] = aiWeight.mWeight;
    }
  }
  return(weights);
}

Matrix[] getBoneOffsets(App app, double animationTime = 0.0f) {
  Matrix[] boneOffsets;
  foreach(obj; app.objects){
    if(obj.bones.length > 0) {
      Matrix[] offsets;
      offsets.length = obj.bones.length;
      app.calculateGlobalTransform(app.animations[app.animation], obj.bones, offsets, app.rootnode, Matrix(), animationTime);
      boneOffsets ~= offsets;
    }
  }
  //SDL_Log("Computed: %d offsets", nOffsets);
  return(boneOffsets);
}

