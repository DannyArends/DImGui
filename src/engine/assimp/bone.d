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
import assimp : name;

struct Bone {
  Matrix offset;
  uint index;
  float[uint] weights;   // Vertices influenced by this bone

  @property float[3] bindPosition() {
    return offset.inverse().position();
  }
}

void loadBones(aiMesh* mesh, ref Bone[string] bones, ref uint bone) {
  for (uint b = 0; b < mesh.mNumBones; b++) {
    auto aiBone = mesh.mBones[b];
    string name = format("%s:%s", mesh.name(), aiBone.name());
    bones[name] = Bone();
    bones[name].offset = cast(float[16])aiBone.mOffsetMatrix;
    bones[name].index = bone + b;
    for (uint w = 0; w < aiBone.mNumWeights; w++) {
      auto aiWeight = aiBone.mWeights[w];
      bones[name].weights[aiWeight.mVertexId] = aiWeight.mWeight;
    }
  }
}

Matrix[] getBoneOffsets(App app, double animationTime = 0.0f) {
  Matrix[] offsets;
  foreach(obj; app.objects){
    foreach(mesh; obj.meshes){
      if(mesh.bones.length > 0) {
        Matrix[] meshOffsets;
        meshOffsets.length = mesh.bones.length;
        app.animations[app.animation].calculateGlobalTransform(mesh.bones, meshOffsets, app.rootnode, Matrix(), animationTime);
        offsets ~= meshOffsets;
      }
    }
  }
  //SDL_Log("Computed %d offsets", offsets.length);
  for (uint o = 0; o < offsets.length; o++) {
    offsets[o] = offsets[o].transpose();
  }
  return(offsets);
}

