/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import matrix : Matrix, translate, scale, multiply;
import quaternion : angleAxis, qMul, rotate;
import vector : vAdd;

/** Per-drawing-symbol spec: which material/size, and whether it advances the turtle. No Geometry here — the turtle is pure. */
struct TurtleBrush {
  int material = -1;
  float radius = 0.1f;
  float length = 1.0f;
  bool advance = true;
}

/** Turtle config: turn angle (degrees) + the per-drawing-symbol brush table. */
struct TurtleConfig {
  float angle = 25.0f;
  TurtleBrush[char] brush;     /// e.g. 'C' -> cone spec, 'I' -> leaf spec
}

private struct State { float[3] pos; float[4] orient; }   // orient = quaternion

/** Interpret an already-iterated L-system string, emitting DrawInstances into the brushes' meshes.
    Turtle local frame: heading is +Y. Turns are applied in the turtle's own frame (right-multiply). */
DrawInstance[][char] interpret(const(char)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  DrawInstance[][char] instances;
  State st = State(origin, orient0);
  State[] stack;
  const float a = cfg.angle;

  foreach(c; symbols) {
    switch(c) {
      case '+': st.orient = qMul(st.orient, angleAxis( a, [0.0f, 0.0f, 1.0f])); break;  // yaw
      case '-': st.orient = qMul(st.orient, angleAxis(-a, [0.0f, 0.0f, 1.0f])); break;
      case '&': st.orient = qMul(st.orient, angleAxis( a, [1.0f, 0.0f, 0.0f])); break;  // pitch
      case '^': st.orient = qMul(st.orient, angleAxis(-a, [1.0f, 0.0f, 0.0f])); break;
      case '<': st.orient = qMul(st.orient, angleAxis( a, [0.0f, 1.0f, 0.0f])); break;  // roll
      case '>': st.orient = qMul(st.orient, angleAxis(-a, [0.0f, 1.0f, 0.0f])); break;
      case '(': stack ~= st; break;
      case ')': if(stack.length){ st = stack[$-1]; stack = stack[0 .. $-1]; } break;
      case 'X': break;                               // rewrite driver, draws nothing
      default:
        if(auto br = c in cfg.brush) {
          Matrix rot = rotate(st.orient);
          Matrix m = translate(st.pos)
                       .multiply(rot)
                       .multiply(translate([0.0f, br.length * 0.5f, 0.0f]))
                       .multiply(scale([br.radius, br.length, br.radius]));
          instances[c] ~= DrawInstance(br.material, m);
          if(br.advance){ st.pos = st.pos.vAdd(rot.multiply([0.0f, br.length, 0.0f])); }
        }
      break;
    }
  }
  return instances;
}
