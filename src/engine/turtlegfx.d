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

