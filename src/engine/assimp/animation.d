/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import bone : Bone;
import node : Node;
import assimp : OpenAsset, name;
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

void calculateGlobalTransform(App app, Geometry obj, ref Matrix[] offsets, Node node, Matrix globalTransform, double animationTime){
  Animation animation = obj.animations[obj.animation];
  Matrix localTransform = node.transform;

  if (node.name in animation.nodeAnimations) {
    auto p = getNodePosition(animation.nodeAnimations[node.name], animationTime);
    auto r = getNodeRotation(animation.nodeAnimations[node.name], animationTime);
    auto s = getNodeScale(animation.nodeAnimations[node.name], animationTime);
    Matrix positionM = translate(Matrix(), p);
    Matrix rotationM = rotate(Matrix(), r);
    Matrix scaleM = scale(Matrix(), s);
    localTransform = scaleM.multiply(positionM.multiply(rotationM));
  }

  Matrix globalOffset = globalTransform.multiply(localTransform);

  if (node.name in app.bones) {
    offsets[app.bones[node.name].index] = globalOffset.multiply(app.bones[node.name].offset);
  }
  foreach(cNode; node.children){
    app.calculateGlobalTransform(obj, offsets, cNode, globalOffset, animationTime);
  }
}

Animation[] loadAnimations(ref App app, OpenAsset asset, aiScene* scene) {
  Animation[] animations;
  if (scene.mNumAnimations > 0) {
    if(app.verbose) SDL_Log("Processing %u animations...", scene.mNumAnimations);
    for (uint i = 0; i < scene.mNumAnimations; i++) {
      auto aiAnim = scene.mAnimations[i];
      Animation anim;
      anim.name = name(aiAnim.mName);
      anim.duration = aiAnim.mDuration;
      anim.ticksPerSecond = aiAnim.mTicksPerSecond != 0 ? aiAnim.mTicksPerSecond : 25.0; // Default to 25 if 0

      if (app.verbose) {
        SDL_Log("  Animation %u: %s (Duration: %.2f ticks, Ticks/Sec: %.2f)", i, toStringz(anim.name), anim.duration, anim.ticksPerSecond);
        SDL_Log("  %u animation channels", aiAnim.mNumChannels);
      }

      for (uint j = 0; j < aiAnim.mNumChannels; j++) {
        auto aiNodeAnim = aiAnim.mChannels[j];
        NodeAnimation nodeAnim;
        string nodeName = format("%s:%s", asset.mName, name(aiNodeAnim.mNodeName));

        if (app.verbose) {
          SDL_Log("    Node Channel %u for '%s'", j, toStringz(nodeName));
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
