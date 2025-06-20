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
  Matrix offset;
  uint index;
  float[uint] weights;   // Vertices influenced by this bone

  @property float[3] bindPosition() {
    return offset.inverse().position();
  }
}

void loadBones(aiMesh* mesh, ref Bone[string] bones, uint bone, uint vert) {
  for (uint b = 0; b < mesh.mNumBones; b++) {
    auto aiBone = mesh.mBones[b];
    string name = aiBone.name();
    bones[name] = Bone();
    bones[name].offset = toMatrix(aiBone.mOffsetMatrix);
    bones[name].index = b;
    for (uint w = 0; w < aiBone.mNumWeights; w++) {
      auto aiWeight = aiBone.mWeights[w];
      bones[name].weights[aiWeight.mVertexId] = aiWeight.mWeight;
    }
  }
}

Matrix[] getBoneOffsets(App app, double animationTime = 0.0f) {
  Matrix[] offsets;
  offsets.length = 1024;
  uint nOffsets = 0;
  foreach(obj; app.objects){
    if(obj.bones.length > 0) {
      app.animations[app.animation].calculateGlobalTransform(obj.bones, offsets, app.rootnode, Matrix(), animationTime);
      nOffsets += obj.bones.length;
    }
  }
  //SDL_Log("Computed: %d offsets", nOffsets);
  return(offsets[0..nOffsets]);
}

