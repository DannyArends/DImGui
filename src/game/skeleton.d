/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import animation : calculateCurrentTick, calculateGlobalTransform;
import bone : mergeBones;
import lsystem : grammar;
import matrix : halfExtent;
import resources : rawConfig;
import turtlegfx : interpretRig, buildClips, rigToNode, rigBones;

/** A pawn's full per-uid rig+animation state. Owned solely by the container's Skeleton[uint] map; never drawn. */
struct Skeleton {
  string name;               /// "Species:skel:uid"
  RigNode[] rig;             /// turtle rig, parent-indexed, walked to emit brush instances
  float[3] dscale;           /// build girth/height, seeded by uid
  float footY;               /// lowest bind-pose Y, to seat feet on the ground
  Node rootnode;             /// posed each frame
  Bone[string] bones;        /// name -> (local index, inverse bind), merged into app.bones
  Animation[] animations;    /// baked clips
  AnimationState state;      /// single clip state
  int region;                /// palette base in boneOffsets
  uint boneBase, boneCount;  /// global bone range
  int[] boneSlot;            /// node k -> local palette slot
}

/** Assign every live pawn skeleton a contiguous palette region and grow the palette to fit. Runs once per frame before posing */
void updateSkeletons(ref GameApp app) {
  uint top = 0;
  foreach(ref o; app.objects) { /// static/loaded skinned assets (e.g. spider.fbx)
    if(o.boneCount == 0) continue;
    foreach(ref inst; o.instances) { inst.instance[3] = cast(int)top; top += o.boneCount; }
  }
  void assign(E)(E entity) {
    if(entity is null) return;
    foreach(uid, ref s; entity.skel) { s.region = cast(int)top; top += s.boneCount; }   // ref: mutate in place
  }
  assign(app.world.dwarves);
  assign(app.world.animals);
  if(top > app.boneOffsets.length) {
    if(app.boneOffsets.length == 0) app.boneOffsets.length = app.boneOffsets.capacity;
    while(app.boneOffsets.length < top) app.boneOffsets.length *= 2;
  }
}

/** Fill a Skeleton's node/bone/animation data from its rig; assigns the local palette slots */
void bakeSkeleton(ref GameApp app, ref Skeleton sk, immutable AnimClip[] clips, string prefix, string name, uint seed) {
  sk.name = name;
  sk.rootnode = rigToNode(sk.rig, prefix);
  sk.bones = rigBones(sk.rig, prefix);
  sk.animations = buildClips(sk.rig, prefix, clips, seed);
  app.mergeBones(sk);
  sk.boneSlot.length = sk.rig.length;
  foreach(k; 0 .. sk.rig.length) sk.boneSlot[k] = cast(int)(app.bones[format("%s%d", prefix, k)].index - sk.boneBase);
}

/** Build (once) the procedural skeleton for an entity uid: seed the grammar by uid so each entity differs */
void buildSkeleton(Container)(ref GameApp app, Container container, uint uid, ref immutable RawT e) {
  if(uid in container.skel) return;
  Skeleton sk;
  auto cfg = rawConfig(e);
  uint hash = uid * 2654435761u;
  sk.rig = interpretRig(grammar(hash, 1, e.axiom, e.rules), cfg, [0,0,0], [0,0,0,1]);
  bool any = false;
  foreach(ref n; sk.rig) { immutable y = n.inst.matrix[13] - n.inst.matrix.halfExtent[1]; if(!any || y < sk.footY) { sk.footY = y; any = true; } }
  immutable v = 1.0f + ((hash & 255) / 255.0f * 2.0f - 1.0f) * e.scaleVariance;
  sk.dscale = [v, v, v];
  app.bakeSkeleton(sk, e.clips, format("%s%u.", e.name, uid), format("%s:skel:%u", e.name, uid), hash);
  container.skel[uid] = sk;
  app.updateSkeletons();
}

/** Select and evaluate a skeleton's clip into its palette region */
void animateSkeleton(Pawn)(ref GameApp app, ref Skeleton s, ref Pawn pawn, ref immutable RawT raw, float dt) {
  if(dt == 0.0f) return;
  uint clip = 0;
  foreach(ci, ref c; raw.clips) { if(c.whenMoving == (pawn.moveT < 1.0f)) { clip = cast(uint)ci; break; } }
  s.state.animation = clip;
  s.state.animTime += dt;
  immutable cT = calculateCurrentTick(s.state.animTime, s.animations[clip].ticksPerSecond, s.animations[clip].duration);
  app.calculateGlobalTransform(s, s.rootnode, Matrix(), cT, clip, cast(uint)s.region);
  app.buffers["BoneMatrices"].invalidate();
}

/** Tear down a skeleton */
void freeSkeleton(Container)(ref GameApp app, Container container, uint uid) {
  if(uid !in container.skel) return;
  foreach(name; container.skel[uid].bones.keys) app.bones.remove(name);
  container.skel.remove(uid);
}
