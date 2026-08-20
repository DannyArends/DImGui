/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import bone : Bone;
import node : Node;
import geometry : Geometry;
import assimp : OpenAsset, name, nodeName;
import vector : interpolate, x, y, z;
import quaternion : slerp, rotate;
import matrix : Matrix, inverse, scale, translate, transpose, multiply;

struct AnimationState {
  uint animation = 0;       /// Current Animation
  double animTime = 0.0;    /// ms of animation played, dt-advanced
}

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

@nogc double calculateCurrentTick(double seconds, double tps, double dur) nothrow { return fmod(seconds * tps, dur); }

/** Advance one animated asset's animation by dt and recompute its bone transforms. */
void animateAsset(T)(ref App app, T obj, float dt) {
  if(dt == 0.0f) return;
  if(obj.states.length != obj.instances.length) {
    size_t old = obj.states.length;
    obj.states.length = obj.instances.length ? obj.instances.length : 1;
    foreach(k; old .. obj.states.length) obj.states[k].animTime = uniform(0.0, 1000.0);
  }
  foreach(i, ref st; obj.states) {
    st.animTime += dt;
    double cT = calculateCurrentTick(st.animTime, obj.animations[st.animation].ticksPerSecond, obj.animations[st.animation].duration);
    app.calculateGlobalTransform(obj, obj.rootnode, Matrix(), cT, st.animation, cast(uint)obj.instances[i].instanceDef[3]);
  }
  app.buffers["AnimatedMatrices"].invalidate();
}

/** Skinned-model driver: sample keyframes, accumulate parent·local, write the animated bone palette. */
void calculateGlobalTransform(T)(ref App app, T obj, const Node node, const Matrix pTransform,
                                 double animationTime, uint animIndex, uint regionBase) {
  Animation animation = obj.animations[animIndex];
  Matrix local = node.transform;
  if (node.name in animation.nodeAnimations) {
    Matrix positionM = translate(sampleKeyframes!interpolate(animation.nodeAnimations[node.name].positionKeys, animationTime));
    Matrix rotationM = rotate(sampleKeyframes!slerp(animation.nodeAnimations[node.name].rotationKeys, animationTime));
    Matrix scaleM = scale(sampleKeyframes!interpolate(animation.nodeAnimations[node.name].scalingKeys, animationTime));
    local = scaleM.multiply(positionM.multiply(rotationM));
  }
  Matrix gTransform = pTransform.multiply(local);
  if (node.name in app.bones) {
    app.animatedOffsets[regionBase + (app.bones[node.name].index - obj.boneBase)] = gTransform.multiply(app.bones[node.name].offset);
  }
  foreach(cNode; node.children) {
    app.calculateGlobalTransform(obj, cNode, gTransform, animationTime, animIndex, regionBase);
  }
}

/** load all animations from aiScene* */
Animation[] loadAnimations(aiScene* scene, const OpenAsset asset, bool verbose = true) {
  Animation[] animations;
  animations.length = scene.mNumAnimations;
  if(verbose) SDL_Log("Processing %u animations...", scene.mNumAnimations);
  for (uint i = 0; i < scene.mNumAnimations; i++) {
    auto aiAnim = scene.mAnimations[i];
    Animation anim;
    anim.name = name(aiAnim.mName);
    anim.duration = aiAnim.mDuration;
    anim.ticksPerSecond = aiAnim.mTicksPerSecond != 0 ? aiAnim.mTicksPerSecond : 24.0;

    if (verbose) {
      SDL_Log("  Animation %u: %s (Duration: %.2f ticks, Ticks/Sec: %.2f)", i, toStringz(anim.name), anim.duration, anim.ticksPerSecond);
      SDL_Log("  %u animation channels", aiAnim.mNumChannels);
    }

    for (uint j = 0; j < aiAnim.mNumChannels; j++) {
      auto aiNodeAnim = aiAnim.mChannels[j];
      NodeAnimation nodeAnim;
      string nodeName = asset.nodeName(name(aiNodeAnim.mNodeName));

      if (verbose) {
        SDL_Log("    Node Channel %u for '%s'", j, toStringz(nodeName));
        SDL_Log("      Position Keys: %u", aiNodeAnim.mNumPositionKeys);
        SDL_Log("      Rotation Keys: %u", aiNodeAnim.mNumRotationKeys);
        SDL_Log("      Scaling Keys: %u", aiNodeAnim.mNumScalingKeys);
      }

      nodeAnim.positionKeys.length = aiNodeAnim.mNumPositionKeys;
      nodeAnim.rotationKeys.length = aiNodeAnim.mNumRotationKeys;
      nodeAnim.scalingKeys.length = aiNodeAnim.mNumScalingKeys;

      for (uint k = 0; k < aiNodeAnim.mNumPositionKeys; k++) {
        auto aiKey = aiNodeAnim.mPositionKeys[k];
        PositionKey posKey = { time : aiKey.mTime, value : [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z] };
        nodeAnim.positionKeys[k] = posKey;
      }
      for (uint k = 0; k < aiNodeAnim.mNumRotationKeys; k++) {
        auto aiKey = aiNodeAnim.mRotationKeys[k];
        RotationKey rotKey = { time : aiKey.mTime, value : [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z, aiKey.mValue.w] };
        nodeAnim.rotationKeys[k] = rotKey;
      }
      for (uint k = 0; k < aiNodeAnim.mNumScalingKeys; k++) {
          auto aiKey = aiNodeAnim.mScalingKeys[k];
          ScalingKey scaleKey = { time : aiKey.mTime, value : [aiKey.mValue.x, aiKey.mValue.y, aiKey.mValue.z] };
          nodeAnim.scalingKeys[k] = scaleKey;
      }
      anim.nodeAnimations[nodeName] = nodeAnim;
    }
    animations[i] = anim;
  }
  return(animations);
}

@nogc pure size_t findKeyframeIndex(T)(const T[] keys, double animationTime) nothrow {
  for (size_t i = 0; i < (keys.length - 1); i++) { if (animationTime < keys[i + 1].time) { return i; } }
  return(keys.length - 1);
}

/** Interpolate a keyframe channel at animationTime; interp = interpolate for vec3, slerp for quats. */
@nogc pure auto sampleKeyframes(alias interp, K)(const K[] keys, double animationTime) nothrow {
  if (keys.length == 1) return keys[0].value;
  size_t i0 = findKeyframeIndex(keys, animationTime);
  size_t i1 = i0 + 1; if (i1 >= keys.length) i1 = i0;
  double t0 = keys[i0].time, t1 = keys[i1].time;
  float factor = (t1 != t0) ? cast(float)((animationTime - t0) / (t1 - t0)) : 0.0f;
  return interp(keys[i0].value, keys[i1].value, factor);
}

