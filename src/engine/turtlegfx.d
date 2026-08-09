/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import lsystem : turnAxis, turnAngle;
import matrix : segmentTransform;
import quaternion : angleAxis, qMul, rotate;
import vector : vAdd;

/** Interpret an already-iterated L-system string, emitting DrawInstances.
    Turtle local frame: heading is +Y. Turns are applied in the turtle's own frame (right-multiply) */
DrawInstance[][char] interpret(const(char)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  DrawInstance[][char] instances;
  TurtleState st = TurtleState(origin, orient0);
  TurtleState[] stack;

  foreach(c; symbols) {
    switch(c) {
      case '(': stack ~= st; break;
      case ')': if(stack.length){ st = stack[$-1]; stack = stack[0 .. $-1]; } break;
      case 'X': break;
      case 'f': { const Matrix R = rotate(st.orient); st.pos = st.pos.vAdd([R[4]*cfg.gap, R[5]*cfg.gap, R[6]*cfg.gap]); } break;   // translate, no draw
      default:
        const ax = turnAxis(c);
        if(ax != [0.0f, 0.0f, 0.0f]) { st.orient = qMul(st.orient, angleAxis(turnAngle(c, cfg), ax)); break; }
        if(auto br = c in cfg.brush) {
          const Matrix R = rotate(st.orient);
          const float[3] o = br.offset;
          const float[3] dp = [st.pos[0] + o[0]*R[0] + o[1]*R[4] + o[2]*R[8],
                               st.pos[1] + o[0]*R[1] + o[1]*R[5] + o[2]*R[9],
                               st.pos[2] + o[0]*R[2] + o[1]*R[6] + o[2]*R[10]];
          instances[c] ~= DrawInstance(segmentTransform(dp, R, br.radius, br.length), br.material, br.color);
          if(br.advance){ st.pos = st.pos.vAdd([R[4]*br.length*0.95f, R[5]*br.length*0.95f, R[6]*br.length*0.95f]); }
        }
      break;
    }
  }
  return instances;
}
