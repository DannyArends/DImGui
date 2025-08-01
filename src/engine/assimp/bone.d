/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import animation : Node, calculateGlobalTransform, calculateCurrentTick;
import assimp : OpenAsset, name, nodeName;
import boundingbox : Bounds;
import matrix : Matrix, toMatrix, multiply, inverse, rotate, scale, position, transpose, translate;
import sdl : STARTUP;
import vector : negate, x,y,z;

/** Our Bone structure matching the GPU
 */
struct Bone {
  Matrix offset;          /// Inverse bind pose matrix
  uint index;             /// Bone index

  @property float[3] bindPosition() {
    return offset.inverse().position();
  }
}

alias float[uint][string] BoneWeights;

/** loadBoneWeights
 * TODO: Should actually not write to globalBones (tread safety issue with threading.d)
 */
BoneWeights loadBoneWeights(OpenAsset asset, aiMesh* mesh, ref Bone[string] globalBones, Matrix pTransform) {
  BoneWeights weights;
  for (uint b = 0; b < mesh.mNumBones; b++) {
    auto aiBone = mesh.mBones[b];
    if (aiBone.mNumWeights == 0) continue; // No weights, no effect, skip
    string name = asset.nodeName(name(aiBone.mName));
    if (!(name in globalBones)) { // New bone, add it to the global bones
      globalBones[name] = Bone();
      globalBones[name].offset = multiply(toMatrix(aiBone.mOffsetMatrix), pTransform.inverse());
      globalBones[name].index = cast(uint)(globalBones.length-1);
    }
    //SDL_Log(toStringz(format("%s.bone: %d -> %d", name, globalBones[name].index, aiBone.mNumWeights)));
    for (uint w = 0; w < aiBone.mNumWeights; w++) {
      auto aiWeight = aiBone.mWeights[w];
      weights[name][aiWeight.mVertexId] = aiWeight.mWeight;
    }
  }
  return(weights);
}

/** updateBoneOffsets
 * compute the new bone offsets for the current frame
 */
void updateBoneOffsets(App app, uint syncIndex) {
  ulong t = SDL_GetTicks() - app.time[STARTUP];
  foreach(ref obj; app.objects) {
    if(obj.animations.length > 0) {
      double cT = calculateCurrentTick(t, obj.animations[obj.animation].ticksPerSecond, obj.animations[obj.animation].duration);
      app.calculateGlobalTransform(obj, obj.rootnode, Matrix(), cT);
    }
  }
  app.buffers["BoneMatrices"].dirty[syncIndex] = true;
}

