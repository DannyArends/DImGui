/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.array : array;
import std.algorithm : map;
import std.string : fromStringz, toStringz;
import std.conv : to;
import std.format : format;

import bone : Bone;
import vector : interpolate;
import quaternion : slerp, rotate;
import matrix : Matrix, inverse, scale, translate, transpose, multiply;

struct NodeAnimation {
  PositionKey[] positionKeys;
  RotationKey[] rotationKeys;
  ScalingKey[] scalingKeys;
}

struct PositionKey {
    double time;
    float[3] value;
}

struct RotationKey {
    double time;
    float[4] value;
}

struct ScalingKey {
    double time;
    float[3] value;
}

struct Animation {
    string name;
    double duration;
    double ticksPerSecond;
    NodeAnimation[string] nodeAnimations;
}

struct Node {
  string name;
  Matrix offset;
  Node[] children;
}

//  aiNode* node = scene.mRootNode;
Node loadNode(aiNode* node, uint lvl = 0) {
  Node n = Node();
  n.name = to!string(fromStringz(node.mName.data));
  n.offset = cast(float[16])node.mTransformation;
//  n.offset = transpose(n.offset);

  n.children.length = node.mNumChildren;
  //SDL_Log("[%d] %s", lvl, toStringz(n.name));
  for (uint i = 0; i < node.mNumChildren; ++i) {
    n.children[i] = loadNode(node.mChildren[i], lvl+1);
  }
  return(n);
}

// Finds the index of a keyframe *before or at* the animation time.
uint findKeyframeIndex(uint numKeys, double[] timeKeys, double animationTime) {
  for (uint i = 0; i < numKeys - 1; ++i) {
    if (animationTime < timeKeys[i + 1]) { return i; }
  }
  return numKeys - 1;
}

void readNodeAnimData(NodeAnimation anim, double animationTime, ref float[3] outPos, ref float[4] outRot, ref float[3] outScale) {
    if (anim.positionKeys.length == 1) outPos = anim.positionKeys[0].value;
    else {
        uint p0Idx = findKeyframeIndex(cast(uint)anim.positionKeys.length, anim.positionKeys.map!(k => k.time).array, animationTime);
        uint p1Idx = p0Idx + 1; if (p1Idx >= anim.positionKeys.length) p1Idx = p0Idx;
        double t0 = anim.positionKeys[p0Idx].time, t1 = anim.positionKeys[p1Idx].time;
        float factor = (t1 != t0) ? cast(float)((animationTime - t0) / (t1 - t0)) : 0.0f;
        outPos = interpolate(anim.positionKeys[p0Idx].value, anim.positionKeys[p1Idx].value, factor);
    }

    if (anim.rotationKeys.length == 1) outRot = anim.rotationKeys[0].value;
    else {
        uint r0Idx = findKeyframeIndex(cast(uint)anim.rotationKeys.length, anim.rotationKeys.map!(k => k.time).array, animationTime);
        uint r1Idx = r0Idx + 1; if (r1Idx >= anim.rotationKeys.length) r1Idx = r0Idx;
        double t0 = anim.rotationKeys[r0Idx].time, t1 = anim.rotationKeys[r1Idx].time;
        float factor = (t1 != t0) ? cast(float)((animationTime - t0) / (t1 - t0)) : 0.0f;
        outRot = slerp(anim.rotationKeys[r0Idx].value, anim.rotationKeys[r1Idx].value, factor);
    }

    if (anim.scalingKeys.length == 1) outScale = anim.scalingKeys[0].value;
    else {
        uint s0Idx = findKeyframeIndex(cast(uint)anim.scalingKeys.length, anim.scalingKeys.map!(k => k.time).array, animationTime);
        uint s1Idx = s0Idx + 1; if (s1Idx >= anim.scalingKeys.length) s1Idx = s0Idx;
        double t0 = anim.scalingKeys[s0Idx].time, t1 = anim.scalingKeys[s1Idx].time;
        float factor = (t1 != t0) ? cast(float)((animationTime - t0) / (t1 - t0)) : 0.0f;
        outScale = interpolate(anim.scalingKeys[s0Idx].value, anim.scalingKeys[s1Idx].value, factor);
    }
}

void calculateGlobalTransform(Animation animation, Bone[string] bones, ref Matrix[] offsets, Node node, Matrix transform, double animationTime){
  Matrix nodeTransform = node.offset;

  if (node.name in animation.nodeAnimations) {
    NodeAnimation nodeAnim = animation.nodeAnimations[node.name];
    float[3] interpolatedPos; float[4] interpolatedRot; float[3] interpolatedScale;
    readNodeAnimData(nodeAnim, animationTime, interpolatedPos, interpolatedRot, interpolatedScale);
    Matrix translationM = translate(Matrix(), interpolatedPos);
    Matrix rotationM = rotate(Matrix(), interpolatedRot);
    Matrix scaleM = scale(Matrix(), interpolatedScale);
    nodeTransform = translationM.multiply(rotationM).multiply(scaleM);
  }

  Matrix gOffset = transform.multiply(nodeTransform);
  SDL_Log(toStringz(format("-----")));
  SDL_Log(toStringz(format("Offset: %s", node.offset)));
  SDL_Log(toStringz(format("Transformed: %s", nodeTransform)));

  if (node.name in bones) {
    offsets[bones[node.name].index] = gOffset.multiply(bones[node.name].offset);
  }
  foreach(cNode; node.children){
    animation.calculateGlobalTransform(bones, offsets, cNode, gOffset, animationTime);
  } 
}

Animation[] loadAnimations(ref App app, aiScene* scene) {
  Animation[] animations;
  if (scene.mNumAnimations > 0) {
    SDL_Log("Processing %u animations...", scene.mNumAnimations);
    for (uint i = 0; i < scene.mNumAnimations; i++) {
      auto aiAnim = scene.mAnimations[i];
      Animation anim;
      anim.name = to!string(fromStringz(aiAnim.mName.data));
      anim.duration = aiAnim.mDuration;
      anim.ticksPerSecond = aiAnim.mTicksPerSecond != 0 ? aiAnim.mTicksPerSecond : 25.0; // Default to 25 if 0

      if (i == app.animation) {
        SDL_Log("  Animation %u: %s (Duration: %.2f ticks, Ticks/Sec: %.2f)", i, anim.name.ptr, anim.duration, anim.ticksPerSecond);
        SDL_Log("  %u animation channels", aiAnim.mNumChannels);
      }

      for (uint j = 0; j < aiAnim.mNumChannels; j++) {
        auto aiNodeAnim = aiAnim.mChannels[j];
        NodeAnimation nodeAnim;
        string nodeName = to!string(fromStringz(aiNodeAnim.mNodeName.data));


        if (app.verbose) {
          SDL_Log("    Node Channel %u for '%s'", j, nodeName.ptr);
          SDL_Log("      Position Keys: %u", aiNodeAnim.mNumPositionKeys);
          SDL_Log("      Rotation Keys: %u", aiNodeAnim.mNumRotationKeys);
          SDL_Log("      Scaling Keys: %u", aiNodeAnim.mNumScalingKeys);
        }

        // Extract Position Keys
        for (uint k = 0; k < aiNodeAnim.mNumPositionKeys; k++) {
          auto aiKey = aiNodeAnim.mPositionKeys[k];
          PositionKey posKey;
          posKey.time = aiKey.mTime / anim.ticksPerSecond; // Convert to seconds
          posKey.value = [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z];
          nodeAnim.positionKeys ~= posKey;
        }

        // Extract Rotation Keys (Quaternions)
        for (uint k = 0; k < aiNodeAnim.mNumRotationKeys; k++) {
          auto aiKey = aiNodeAnim.mRotationKeys[k];
          RotationKey rotKey;
          rotKey.time = aiKey.mTime / anim.ticksPerSecond; // Convert to seconds
          rotKey.value = [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z, aiKey.mValue.w];
          nodeAnim.rotationKeys ~= rotKey;
        }

        // Extract Scaling Keys
        for (uint k = 0; k < aiNodeAnim.mNumScalingKeys; k++) {
            auto aiKey = aiNodeAnim.mScalingKeys[k];
            ScalingKey scaleKey;
            scaleKey.time = aiKey.mTime / anim.ticksPerSecond; // Convert to seconds
            scaleKey.value = [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z];
            nodeAnim.scalingKeys ~= scaleKey;
        }
        anim.nodeAnimations[nodeName] = nodeAnim;
      }
      animations ~= anim;
    }
  }
  return(animations);
}
