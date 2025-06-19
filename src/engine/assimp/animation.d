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
import node : Node;
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

void calculateGlobalTransform(Animation animation, Bone[string] bones, ref Matrix[] offsets, Node node, Matrix transform, double animationTime){
  Matrix gOffset = transform.multiply(node.offset);

  if (node.name in bones) {
    offsets[bones[node.name].index] = gOffset;//.multiply(bones[node.name].offset);
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
