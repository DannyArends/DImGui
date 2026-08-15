/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import lsystem : buildGrammar, turnAxis, turnAngle;
import matrix : segmentTransform, position, inverse, multiply;
import quaternion : angleAxis, quatAxisAngle, qMul, rotate, toQuaternion;
import vector : vAdd;

/** One rigid part emitted by the turtle walk: a brush instance plus its place in the rig tree. */
struct RigNode {
  int parent = -1;      /// index of parent RigNode in the returned array; -1 == root
  Matrix local;         /// transform relative to parent (world == parent.world · local)
  DrawInstance inst;    /// draw instance: world matrix (bind pose) + material + color
  char symbol;          /// brush symbol -> shared geometry
}

/** One keyframe from the time-walk: a step index and the cursor euler (degrees) recorded for a bone. */
struct PoseKey {
  int step;
  float[4] quat;
}

/** One animation primitive: a clip symbol that writes the pose cursor onto a target bone symbol. */
struct PoseBrush {
  char target;                            /// brush symbol (bone) this pose writes a key to
  bool bySide = false;                    /// mirror the cursor by the bone's left/right sign
  float[3] axis = [0.0f, 0.0f, 0.0f];     /// if non-zero: swing about this WORLD axis (ignores bind orientation)
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

/** Node tree calculateGlobalTransform walks: rigid joint frames, node k named `prefix~k`. */
Node rigToNode(const RigNode[] rig, string prefix) {
  Matrix[] J; J.length = rig.length;
  foreach(k, ref n; rig) J[k] = jointWorld(n);
  Node[] nodes; nodes.length = rig.length;
  foreach(k, ref n; rig) nodes[k] = Node(format("%s%d", prefix, k), 0, (n.parent < 0) ? J[k] : J[n.parent].inverse().multiply(J[k]));
  foreach_reverse(k, ref n; rig) if(n.parent >= 0) nodes[n.parent].children ~= nodes[k];
  Node root = Node(prefix ~ "root", 0, Matrix());
  foreach(k, ref n; rig) if(n.parent < 0) root.children ~= nodes[k];
  return root;
}

/** One bone per node; offset = jointWorld^-1 . bindWorld so a UNIT primitive at bone k lands as that segment. */
Bone[string] rigBones(const RigNode[] rig, string prefix) {
  Bone[string] bones;
  foreach(k, ref n; rig) bones[format("%s%d", prefix, k)] = Bone(jointWorld(n).inverse().multiply(n.inst.matrix), cast(uint)k);
  return bones;
}

/** Bake a species' authored clips into NodeAnimation tracks (raw order; index 0 = default). */
Animation[] buildClips(const RigNode[] rig, string prefix, immutable AnimClip[] clips, uint seed) {
  Animation[] anims;
  foreach(ref c; clips) anims ~= clipAnimation(rig, prefix, c, seed);
  return anims;
}

/** One pose's contribution to a bone's local rotation at a key: world-axis swing (body frame) or cursor swing. */
Matrix poseLocal(ref immutable PoseBrush pb, const float[4] quat, float side, const Matrix localJ, const Matrix Rr) {
  if(pb.axis != [0.0f, 0.0f, 0.0f]) {
    const float ang = quatAxisAngle(quat, pb.axis) * (pb.bySide ? side : 1.0f);
    return rotate(angleAxis(ang, pb.axis)).multiply(localJ);
  }
  const float[4] q = (pb.bySide && side < 0.0f) ? [-quat[0], -quat[1], -quat[2], quat[3]] : quat;
  return rotate(q).multiply(Rr);
}

/** Compose every axis-pose targeting a bone at one key (multi-pose bones must name an axis). */
Matrix posesLocal(const char[] syms, ref immutable AnimClip clip, const PoseKey[][char] tracks, size_t i, float side, const Matrix localJ) {
  Matrix rot = Matrix();
  foreach(sym; syms) {
    const pb = clip.poses[sym];
    const float ang = quatAxisAngle(tracks[sym][i].quat, pb.axis) * (pb.bySide ? side : 1.0f);
    rot = rotate(angleAxis(ang, pb.axis)).multiply(rot);
  }
  return rot.multiply(localJ);
}

/** Bake the keyframe track for one rig node from all clip poses that target its symbol. */
NodeAnimation nodeAnimation(ref const RigNode n, const char[] syms, ref immutable AnimClip clip, const PoseKey[][char] tracks, const Matrix localJ) {
  const float side = n.inst.matrix[12] < 0.0f ? -1.0f : 1.0f;
  Matrix Rr = localJ; Rr[12] = 0.0f; Rr[13] = 0.0f; Rr[14] = 0.0f;
  size_t nkeys = tracks[syms[0]].length;
  foreach(sym; syms) if(tracks[sym].length < nkeys) nkeys = tracks[sym].length;
  NodeAnimation na;
  na.positionKeys = [PositionKey(0.0, position(localJ))];
  na.scalingKeys  = [ScalingKey(0.0, [1.0f, 1.0f, 1.0f])];
  na.rotationKeys.length = nkeys;
  foreach(i; 0 .. nkeys) {
    Matrix local = (syms.length == 1) ? poseLocal(clip.poses[syms[0]], tracks[syms[0]][i].quat, side, localJ, Rr)
                                      : posesLocal(syms, clip, tracks, i, side, localJ);
    na.rotationKeys[i] = RotationKey(cast(double)tracks[syms[0]][i].step, toQuaternion(local));
  }
  return na;
}

/** Bake one AnimClip: walk its L-system in time, then map each target symbol's key stream onto every matching rig node. */
Animation clipAnimation(const RigNode[] rig, string prefix, ref immutable AnimClip clip, uint seed) {
  char[char] poses; foreach(sym, ref pb; clip.poses) poses[sym] = pb.target;
  int steps;
  TurtleConfig cfg = { yaw: clip.turn, pitch: clip.turn, roll: clip.turn };
  auto tracks = interpretAnim(buildGrammar(seed, 1, clip.axiom, clip.rules), cfg, poses, steps);

  Animation a = { name: clip.name, duration: cast(double)steps, ticksPerSecond: clip.fps };
  Matrix[] J; J.length = rig.length; foreach(k, ref n; rig) J[k] = jointWorld(n);
  foreach(k, ref n; rig) {
    char[] syms; foreach(sym, ref b; clip.poses) if(b.target == n.symbol && sym in tracks) syms ~= sym;
    if(syms.length == 0) continue;
    const Matrix localJ = (n.parent < 0) ? J[k] : J[n.parent].inverse().multiply(J[k]);
    a.nodeAnimations[format("%s%d", prefix, k)] = nodeAnimation(n, syms, clip, tracks, localJ);
  }
  return a;
}

/** Walk an animation L-system in TIME: `f` advances a step, +/-/&/^/</> rotate the cursor,
 *  `()` branch the cursor, a pose symbol records the cursor onto its target bone symbol.
 *  Returns per-target-symbol key streams + the total step count (clip duration). */
PoseKey[][char] interpretAnim(const(char)[] symbols, const TurtleConfig cfg, const char[char] poses, out int steps) {
  PoseKey[][char] tracks;
  float[4] orient = [0.0f, 0.0f, 0.0f, 1.0f];
  float[4][] stack;
  int t = 0;
  foreach(c; symbols) {
    switch(c) {
      case '(': stack ~= orient; break;
      case ')': if(stack.length){ orient = stack[$-1]; stack = stack[0 .. $-1]; } break;
      case 'X': break;
      case 'f': t++; break;
      default:
        const ax = turnAxis(c);
        if(ax != [0.0f, 0.0f, 0.0f]) { orient = qMul(orient, angleAxis(turnAngle(c, cfg), ax)); break; }
        if(c in poses) tracks[c] ~= PoseKey(t, orient);
      break;
    }
  }
  steps = (t > 0) ? t : 1;
  return tracks;
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
        if(ax != [0.0f, 0.0f, 0.0f]) { st.orient = qMul(st.orient, angleAxis(turnAngle(c, cfg), ax)); break; }
        if(auto br = c in cfg.brush) {
          const Matrix R = rotate(st.orient);
          const float[3] o = br.offset;
          const float[3] dp = [st.pos[0] + o[0]*R[0] + o[1]*R[4] + o[2]*R[8],
                               st.pos[1] + o[0]*R[1] + o[1]*R[5] + o[2]*R[9],
                               st.pos[2] + o[0]*R[2] + o[1]*R[6] + o[2]*R[10]];
          nodes ~= RigNode(current, Matrix(), DrawInstance(segmentTransform(dp, R, br.radius, br.length), br.material, br.color), c);
          current = cast(int)nodes.length - 1;
          if(br.advance){ st.pos = st.pos.vAdd([R[4]*br.length*0.95f, R[5]*br.length*0.95f, R[6]*br.length*0.95f]); }
        }
      break;
    }
  }
  foreach(ref n; nodes) n.local = (n.parent < 0) ? n.inst.matrix : nodes[n.parent].inst.matrix.inverse().multiply(n.inst.matrix);
  return nodes;
}

/** Flattened turtle walk: per brush symbol, the world-space DrawInstances (branch hierarchy discarded).
 *  Thin wrapper over interpretRig — used by static features (trees) that never re-pose. */
DrawInstance[][char] interpret(const(char)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  DrawInstance[][char] instances;
  foreach(ref n; interpretRig(symbols, cfg, origin, orient0)) instances[n.symbol] ~= n.inst;
  return instances;
}

