/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import animation : calculateCurrentTick, calculateGlobalTransform;
import assimp : name, nodeName, OpenAsset;
import matrix : inverse, Matrix, multiply, position, toMatrix;
import sdl : STARTUP;

/** Our Bone structure matching the GPU */
struct Bone {
  Matrix offset;          /// Inverse bind pose matrix
  uint index;             /// Bone index

  @property float[3] bindPosition() {
    return offset.inverse().position();
  }
}

alias float[uint][string] BoneWeights;

/** loadBoneWeights - writes to asset-local bones, merged into app.bones on main thread */
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

/** Propagate any animation changes (made by onFrame handlers) into the per-syncIndex BoneMatrices SSBO. */
void updateBoneOffsets(App app, uint syncIndex) {
  bool any = false;
  foreach(ref obj; app.objects) if(obj.boneDirty) { any = true; break; }
  if(any) app.buffers["BoneMatrices"].dirty[syncIndex] = true;
}

void mergeBones(ref App app, ref OpenAsset obj) {
  uint[uint] indexMap;
  foreach(boneName, ref bone; obj.bones) {
    if(!(boneName in app.bones)) {
      uint newIndex = cast(uint)app.bones.length;
      indexMap[bone.index] = newIndex;
      bone.index = newIndex;
      app.bones[boneName] = bone;
    } else { indexMap[bone.index] = app.bones[boneName].index; }
  }
  foreach(ref v; obj.vertices) {
    for(uint i = 0; i < v.bones.length; i++) { if(v.bones[i] in indexMap) v.bones[i] = indexMap[v.bones[i]]; }
  }
  // Grow CPU-side boneOffsets; the GPU BoneMatrices buffer grows lazily in updateSSBO when it overflows.
  if(app.bones.length > app.boneOffsets.length) {
    if(app.boneOffsets.length == 0) app.boneOffsets.length = app.boneOffsets.capacity;
    while(app.boneOffsets.length < app.bones.length) app.boneOffsets.length *= 2;
  }
}

