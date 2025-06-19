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
    string name = aiBone.name();
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
  offsets.length = 1024;
  foreach(obj; app.objects){
    if(obj.bones.length > 0) {
      foreach(bone; obj.bones){
        SDL_Log("offsets = %d", offsets.length);
        app.animations[app.animation].calculateGlobalTransform(bone, offsets, app.rootnode, Matrix(), animationTime);
      }
    }
  }
  SDL_Log("Computed %d offsets", offsets.length);
  for (uint o = 0; o < offsets.length; o++) { 
    SDL_Log(toStringz(format("%s", offsets[o])));
    offsets[o] = offsets[o].transpose(); }
  return(offsets);
}

