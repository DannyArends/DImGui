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
import assimp : name;
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

size_t findKeyframeIndex(double[] timeKeys, double animationTime) {
  for (size_t i = 0; i < (timeKeys.length - 1); i++) {
    if (animationTime < timeKeys[i + 1]) { return i; }
  }
  return timeKeys.length - 1;
}

float[3] getNodePosition(NodeAnimation anim, double animationTime) {
  if (anim.positionKeys.length == 1) return(anim.positionKeys[0].value);

  size_t i0 = findKeyframeIndex(anim.positionKeys.map!(k => k.time).array, animationTime);
  size_t i1 = i0 + 1; if (i1 >= anim.positionKeys.length) i1 = i0;
  double t0 = anim.positionKeys[i0].time, t1 = anim.positionKeys[i1].time;
  float factor = (t1 != t0) ? cast(float)((animationTime - t0) / (t1 - t0)) : 0.0f;
  return(interpolate(anim.positionKeys[i0].value, anim.positionKeys[i1].value, factor));
}

float[4] getNodeRotation(NodeAnimation anim, double animationTime) {
  if (anim.rotationKeys.length == 1) return(anim.rotationKeys[0].value);

  size_t i0 = findKeyframeIndex(anim.rotationKeys.map!(k => k.time).array, animationTime);
  size_t i1 = i0 + 1; if (i1 >= anim.rotationKeys.length) i1 = i0;
  double t0 = anim.rotationKeys[i0].time, t1 = anim.rotationKeys[i1].time;
  float factor = (t1 != t0) ? cast(float)((animationTime - t0) / (t1 - t0)) : 0.0f;
  return(slerp(anim.rotationKeys[i0].value, anim.rotationKeys[i1].value, factor));
}

float[3] getNodeScale(NodeAnimation anim, double animationTime) {
  if (anim.scalingKeys.length == 1) return(anim.scalingKeys[0].value);

  size_t i0 = findKeyframeIndex(anim.scalingKeys.map!(k => k.time).array, animationTime);
  size_t i1 = i0 + 1; if (i1 >= anim.scalingKeys.length) i1 = i0;
  double t0 = anim.scalingKeys[i0].time, t1 = anim.scalingKeys[i1].time;
  float factor = (t1 != t0) ? cast(float)((animationTime - t0) / (t1 - t0)) : 0.0f;
  return(interpolate(anim.scalingKeys[i0].value, anim.scalingKeys[i1].value, factor));
}

void calculateGlobalTransform(Animation animation, Bone[string] bones, ref Matrix[] offsets, Node node, Matrix transform, double animationTime){
  Matrix nodeTransform;

  if (node.name in animation.nodeAnimations) {
    auto p = getNodePosition(animation.nodeAnimations[node.name], animationTime);
    auto r = getNodeRotation(animation.nodeAnimations[node.name], animationTime);
    auto s = getNodeScale(animation.nodeAnimations[node.name], animationTime);
    Matrix positionM = translate(Matrix(), p);
    Matrix rotationM = rotate(Matrix(), r);
    Matrix scaleM = scale(Matrix(), s);
    nodeTransform = (transpose(positionM)).multiply(scaleM.multiply(rotationM));
  }
  Matrix gOffset = transform.multiply(nodeTransform);

  if (node.name in bones) {
    offsets[bones[node.name].index] = gOffset.multiply(bones[node.name].offset).transpose();
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
      anim.name = aiAnim.name();
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

        for (uint k = 0; k < aiNodeAnim.mNumPositionKeys; k++) {        // Extract Position Keys
          auto aiKey = aiNodeAnim.mPositionKeys[k];
          PositionKey posKey = { time : aiKey.mTime / anim.ticksPerSecond, value : [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z] };
          nodeAnim.positionKeys ~= posKey;
        }
        for (uint k = 0; k < aiNodeAnim.mNumRotationKeys; k++) {        // Extract Rotation Keys (Quaternions)
          auto aiKey = aiNodeAnim.mRotationKeys[k];
          RotationKey rotKey = { time : aiKey.mTime / anim.ticksPerSecond, value : [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z, aiKey.mValue.w] };
          nodeAnim.rotationKeys ~= rotKey;
        }
        for (uint k = 0; k < aiNodeAnim.mNumScalingKeys; k++) {        // Extract Scaling Keys
            auto aiKey = aiNodeAnim.mScalingKeys[k];
            ScalingKey scaleKey = { time : aiKey.mTime / anim.ticksPerSecond, value : [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z] };
            nodeAnim.scalingKeys ~= scaleKey;
        }
        anim.nodeAnimations[nodeName] = nodeAnim;
      }
      animations ~= anim;
    }
  }
  return(animations);
}

