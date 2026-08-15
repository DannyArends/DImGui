/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import lsystem : turnAxis, turnAngle;
import matrix : segmentTransform, inverse, multiply;
import quaternion : angleAxis, qMul, rotate;
import vector : vAdd;

/** One rigid part emitted by the turtle walk: a brush instance plus its place in the rig tree. */
struct RigNode {
  int parent = -1;      /// index of parent RigNode in the returned array; -1 == root
  Matrix local;         /// transform relative to parent (world == parent.world · local)
  DrawInstance inst;    /// draw instance: world matrix (bind pose) + material + color
  char symbol;          /// brush symbol -> shared geometry
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

/** One keyframe from the time-walk: a step index and the cursor euler (degrees) recorded for a bone. */
struct PoseKey { int step; float[4] quat; }

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
        if(auto tgt = c in poses) tracks[*tgt] ~= PoseKey(t, orient);
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

