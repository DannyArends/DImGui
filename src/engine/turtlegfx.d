/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import lsystem : buildGrammar, turnAxis, turnAngle;
import matrix : segmentTransform, position, inverse, multiply;
import quaternion : angleAxis, quatAxisAngle, qMul, rotate, toQuaternion;
import vector : vAdd;

enum float[3] NO_AXIS = [0.0f, 0.0f, 0.0f];         /// PoseBrush.axis sentinel: use cursor frame, not a world axis

/** One rigid part emitted by the turtle walk: a brush instance plus its place in the rig tree. */
struct RigNode {
  int parent = -1;      /// index of parent RigNode in the returned array; -1 == root
  Matrix local;         /// transform relative to parent (world == parent.world · local)
  DrawInstance inst;    /// draw instance: world matrix (bind pose) + material + color
  char symbol;          /// brush symbol -> shared geometry
}

/** One keyframe from the time-walk: the step index and the cursor quaternion recorded for a bone. */
struct PoseKey {
  int step;         /// clip tick this key lands on
  float[4] quat;    /// accumulated cursor orientation at that step
}

/** One animation primitive: a clip symbol that writes the pose cursor onto a target bone symbol. */
struct PoseBrush {
  char target;                            /// brush symbol (bone) this pose writes a key to
  bool bySide = false;                    /// mirror the cursor by the bone's left/right sign
  float[3] axis = NO_AXIS;     /// if non-zero: swing about this WORLD axis (ignores bind orientation)
}

/** Everything the per-step bake needs for one rig node. */
struct PoseCtx {
  const(char)[] syms;                 /// clip symbols targeting this bone
  const(PoseKey[][char]) tracks;      /// baked key streams, by symbol
  float side;                         /// left/right mirror sign (from bind X)
  Matrix localJ;                      /// node's rigid local (rotation + position)
  Matrix Rr;                          /// localJ with translation stripped (cursor frame)
}

/** An animation as its own L-system, walked in TIME -> baked into NodeAnimation tracks. */
struct AnimClip {
  string name;              /// "walk", "idle", ...
  string axiom = "";        /// clip L-system start symbols
  Rule[] rules;             /// clip production rules
  PoseBrush[char] poses;    /// symbol -> which bone it poses
  bool whenMoving = false;  /// select walk vs idle
  float fps = 8.0f;         /// steps per second (drives ticksPerSecond)
  float turn = 25.0f;       /// degrees per turn symbol (swing amplitude)
}

string boneName(string prefix, size_t k) { return format("%s%d", prefix, k); }

/** Rigid joint frame of a rig node: normalized bind rotation, origin at the segment base (the pivot). */
@nogc Matrix jointWorld(ref const RigNode n) nothrow {
  const Matrix M = n.inst.matrix;
  const float lx = sqrt(M[0]*M[0]+M[1]*M[1]+M[2]*M[2]);
  const float ly = sqrt(M[4]*M[4]+M[5]*M[5]+M[6]*M[6]);
  const float lz = sqrt(M[8]*M[8]+M[9]*M[9]+M[10]*M[10]);
  Matrix J;
  J[0]=M[0]/lx; J[1]=M[1]/lx; J[2]=M[2]/lx;
  J[4]=M[4]/ly; J[5]=M[5]/ly; J[6]=M[6]/ly;
  J[8]=M[8]/lz; J[9]=M[9]/lz; J[10]=M[10]/lz;
  J[12]=M[12]-0.5f*M[4]; J[13]=M[13]-0.5f*M[5]; J[14]=M[14]-0.5f*M[6];
  return J;
}

/** Rigid joint frame of every rig node, indexed like `rig`. */
Matrix[] jointWorlds(const RigNode[] rig) nothrow {
  auto J = new Matrix[](rig.length);
  foreach(k, ref n; rig) J[k] = jointWorld(n);
  return J;
}

/** Node tree calculateGlobalTransform walks: rigid joint frames, node k named `prefix~k`. */
Node rigToNode(const RigNode[] rig, string prefix) {
  Matrix[] J = jointWorlds(rig);
  Node[] nodes = new Node[](rig.length);
  foreach(k, ref n; rig) { nodes[k] = Node(boneName(prefix, k), 0, (n.parent < 0) ? J[k] : J[n.parent].inverse().multiply(J[k])); }
  foreach_reverse(k, ref n; rig) { if(n.parent >= 0) { nodes[n.parent].children ~= nodes[k]; } }
  Node root = Node(prefix ~ "root", 0, Matrix());
  foreach(k, ref n; rig) { if(n.parent < 0) { root.children ~= nodes[k]; } }
  return(root);
}

/** One bone per node; offset = jointWorld^-1 . bindWorld so a UNIT primitive at bone k lands as that segment. */
Bone[string] rigBones(const RigNode[] rig, string prefix) {
  Bone[string] bones;
  foreach(k, ref n; rig) { bones[boneName(prefix, k)] = Bone(jointWorld(n).inverse().multiply(n.inst.matrix), cast(uint)k); }
  return(bones);
}

/** Bake a species' authored clips into NodeAnimation tracks (raw order; index 0 = default). */
Animation[] buildClips(const RigNode[] rig, string prefix, immutable AnimClip[] clips, uint seed) {
  Animation[] anims;
  foreach(ref c; clips) { anims ~= clipAnimation(rig, prefix, c, seed); }
  return(anims);
}

/** One pose's contribution to a bone's local rotation at a key: world-axis swing (body frame) or cursor swing. */
Matrix poseLocal(ref immutable PoseBrush pb, const float[4] quat, float side, const Matrix localJ, const Matrix Rr) {
  if(pb.axis != NO_AXIS) {
    const float ang = quatAxisAngle(quat, pb.axis) * (pb.bySide ? side : 1.0f);
    return rotate(angleAxis(ang, pb.axis)).multiply(localJ);
  }
  const float[4] q = (pb.bySide && side < 0.0f) ? [-quat[0], -quat[1], -quat[2], quat[3]] : quat;
  return(rotate(q).multiply(Rr));
}

/** Sample a symbol's track at time `step`: the last key at or before it (hold-last), else identity. */
float[4] quatAtStep(const PoseKey[] keys, int step) {
  float[4] q = Quaternion.init;
  foreach(ref pk; keys) {
    if(pk.step > step) break;
    q = pk.quat;
  }
  return(q);
}

/** Local rotation for a node at one step: compose axis-poses, or the single cursor pose. */
Matrix stepLocal(ref const PoseCtx c, ref immutable AnimClip clip, int step) {
  const first = clip.poses[c.syms[0]];
  if(first.axis != NO_AXIS) { return(posesLocal(c, clip, step)); }
  return(poseLocal(first, quatAtStep(c.tracks[c.syms[0]], step), c.side, c.localJ, c.Rr));
}

/** Compose every axis-pose targeting a bone at one step. */
Matrix posesLocal(ref const PoseCtx c, ref immutable AnimClip clip, int step) {
  Matrix rot = Matrix();
  foreach(sym; c.syms) {
    const pb = clip.poses[sym];
    const float ang = quatAxisAngle(quatAtStep(c.tracks[sym], step), pb.axis) * (pb.bySide ? c.side : 1.0f);
    rot = rotate(angleAxis(ang, pb.axis)).multiply(rot);
  }
  return(rot.multiply(c.localJ));
}

/** Bake the keyframe track for one rig node from all clip poses that target its symbol. */
NodeAnimation nodeAnimation(ref const RigNode n, const char[] syms, ref immutable AnimClip clip, const PoseKey[][char] tracks, const Matrix localJ) {
  Matrix Rr = localJ; Rr[12] = 0.0f; Rr[13] = 0.0f; Rr[14] = 0.0f;
  auto c = PoseCtx(syms, tracks, (n.inst.matrix[12] < 0.0f) ? -1.0f : 1.0f, localJ, Rr);

  int[] steps;
  foreach(sym; syms) { foreach(ref pk; tracks[sym]) { if(!steps.canFind(pk.step)) { steps ~= pk.step; } } }
  steps.sort();

  NodeAnimation na = {positionKeys: [PositionKey(0.0, position(localJ))], scalingKeys:  [ScalingKey(0.0, [1.0f, 1.0f, 1.0f])]};
  na.rotationKeys.length = steps.length;
  foreach(i, step; steps) {
    na.rotationKeys[i] = RotationKey(cast(double)step, toQuaternion(stepLocal(c, clip, step)));
  }
  return(na);
}

/** Bake one AnimClip: walk its L-system in time, then map each target symbol's key stream onto every matching rig node. */
Animation clipAnimation(const RigNode[] rig, string prefix, ref immutable AnimClip clip, uint seed) {
  char[char] poses; foreach(sym, ref pb; clip.poses) poses[sym] = pb.target;
  int steps;
  TurtleConfig cfg = { yaw: clip.turn, pitch: clip.turn, roll: clip.turn };
  auto tracks = interpretAnim(buildGrammar(seed, 1, clip.axiom, clip.rules), cfg, poses, steps);

  Animation a = { name: clip.name, duration: cast(double)steps, ticksPerSecond: clip.fps };
  auto J = jointWorlds(rig);
  foreach(k, ref n; rig) {
    char[] syms;
    foreach(sym, ref b; clip.poses) { if(b.target == n.symbol && sym in tracks) { syms ~= sym; } }
    if(syms.length == 0) continue;
    const Matrix localJ = (n.parent < 0) ? J[k] : J[n.parent].inverse().multiply(J[k]);
    a.nodeAnimations[boneName(prefix, k)] = nodeAnimation(n, syms, clip, tracks, localJ);
  }
  return(a);
}

/** Walk an animation L-system in TIME: `f` advances a step, +/-/&/^/</> rotate the cursor,
 *  '()' branch the cursor, a pose symbol records the cursor onto its target bone symbol.
 *  Returns per-target-symbol key streams + the total step count (clip duration). */
PoseKey[][char] interpretAnim(const(char)[] symbols, const TurtleConfig cfg, const char[char] poses, out int steps) {
  PoseKey[][char] tracks;
  float[4][char] cursor;                          // independent accumulated orientation per pose symbol
  float[4] pending = [0.0f, 0.0f, 0.0f, 1.0f];    // turns since the last pose, applied to the NEXT pose only
  int t = 0;
  foreach(c; symbols) {
    switch(c) {
      case 'X': break;
      case 'f': t++; break;
      default:
        const ax = turnAxis(c);
        if(ax != NO_AXIS) { pending = qMul(pending, angleAxis(turnAngle(c, cfg), ax)); break; }
        if(c in poses) {
          if(c !in cursor) cursor[c] = Quaternion.init;
          cursor[c] = qMul(cursor[c], pending);           // accumulate this pose's own turns (oscillates via +/-)
          tracks[c] ~= PoseKey(t, cursor[c]);
          pending = Quaternion.init;
        }
      break;
    }
  }
  steps = (t > 0) ? t : 1;
  return(tracks);
}

/** Turtle walk that RETAINS the branch hierarchy: each drawn brush becomes a RigNode with a parent
 *  (the enclosing part) and a local transform, so a joint can be re-posed and its children follow. */
RigNode[] interpretRig(const(char)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  RigNode[] nodes;
  TurtleState st = TurtleState(origin, orient0);
  TurtleState[] stack;
  int current = -1;         // most-recent drawn node at this depth == parent for the next draw
  int[] parentStack;

  foreach(c; symbols) {
    switch(c) {
      case '(': stack ~= st; parentStack ~= current; break;
      case ')': if(stack.length){ st = stack[$-1]; stack = stack[0 .. $-1];
                                  current = parentStack[$-1]; parentStack = parentStack[0 .. $-1]; } break;
      case 'X': break;
      case 'f': { const Matrix R = rotate(st.orient); st.pos = st.pos.vAdd([R[4]*cfg.gap, R[5]*cfg.gap, R[6]*cfg.gap]); } break;
      default:
        const ax = turnAxis(c);
        if(ax != NO_AXIS) { st.orient = qMul(st.orient, angleAxis(turnAngle(c, cfg), ax)); break; }
        if(auto br = c in cfg.brush) {
          const Matrix R = rotate(st.orient);
          const float[3] o = br.offset;
          const float[3] dp = [st.pos[0] + o[0]*R[0] + o[1]*R[4] + o[2]*R[8],
                               st.pos[1] + o[0]*R[1] + o[1]*R[5] + o[2]*R[9],
                               st.pos[2] + o[0]*R[2] + o[1]*R[6] + o[2]*R[10]];
          nodes ~= RigNode(current, Matrix(), DrawInstance(segmentTransform(dp, R, br.radius, br.length, br.depth), br.material, br.color), c);
          current = cast(int)nodes.length - 1;
          if(br.advance){ st.pos = st.pos.vAdd([R[4]*br.length*0.95f, R[5]*br.length*0.95f, R[6]*br.length*0.95f]); }
        }
      break;
    }
  }
  foreach(ref n; nodes) { n.local = (n.parent < 0) ? n.inst.matrix : nodes[n.parent].inst.matrix.inverse().multiply(n.inst.matrix); }
  return(nodes);
}

/** Flattened turtle walk: per brush symbol, the world-space DrawInstances (branch hierarchy discarded).
 *  Thin wrapper over interpretRig — used by static features (trees) that never re-pose. */
DrawInstance[][char] interpret(const(char)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  DrawInstance[][char] instances;
  foreach(ref n; interpretRig(symbols, cfg, origin, orient0)) instances[n.symbol] ~= n.inst;
  return(instances);
}

