/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.array : array;
import std.algorithm : sort;
import std.conv : to;
import std.format : format;
import std.string : toStringz, lastIndexOf, fromStringz;

import matrix : Matrix, inverse, position, transpose;
import animation : Node, calculateGlobalTransform;

struct Bone {
  Matrix offset;
  uint index;
  float[uint] weights;   // Vertices influenced by this bone

  @property float[3] bindPosition() {
    return offset.inverse().position();
  }
}

void loadBones(aiMesh* mesh, ref Bone[string] bones) {
  for (uint b = 0; b < mesh.mNumBones; b++) {
    auto aiBone = mesh.mBones[b];
    string name = to!string(fromStringz(aiBone.mName.data));
    //SDL_Log("Bone: %s", toStringz(name));
    bones[name] = Bone();
    bones[name].offset = cast(float[16])aiBone.mOffsetMatrix;
//    bones[name].offset = transpose(bones[name].offset);

    bones[name].index = b;
    for (uint w = 0; w < aiBone.mNumWeights; w++) {
      auto aiWeight = aiBone.mWeights[w];
      bones[name].weights[aiWeight.mVertexId] = aiWeight.mWeight;
    }
  }
}

Matrix[] getBoneOffsets(App app, double animationTime = 0.0f) {
  Matrix[] offsets;
  foreach(obj; app.objects){
    if(obj.bones.length > 0) {
      offsets.length = obj.bones.length;
      app.animations[app.animation].calculateGlobalTransform(obj.bones, offsets, app.rootnode, Matrix(), animationTime);
    }
  }
  //SDL_Log("Computed %d offsets", offsets.length);
  for (uint o = 0; o < offsets.length; o++) {
    offsets[o] = offsets[o].transpose();
  }
  return(offsets);
}

