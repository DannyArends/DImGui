/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import matrix : translate, scale, multiply, segmentTransform ;
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

/** Signed rotation axis for a turn symbol (sign folded into the axis), zeros if not a turn. */
private float[3] turnAxis(char c) pure nothrow @nogc @safe {
  switch(c) {
    case '+': return [0.0f, 0.0f,  1.0f];  case '-': return [0.0f, 0.0f, -1.0f];  // yaw   (Z)
    case '&': return [1.0f, 0.0f,  0.0f];  case '^': return [-1.0f, 0.0f, 0.0f];  // pitch (X)
    case '<': return [0.0f, 1.0f,  0.0f];  case '>': return [0.0f, -1.0f, 0.0f];  // roll  (Y)
    default:  return [0.0f, 0.0f,  0.0f];
  }
}

/** Interpret an already-iterated L-system string, emitting DrawInstances into the brushes' meshes.
    Turtle local frame: heading is +Y. Turns are applied in the turtle's own frame (right-multiply). */
DrawInstance[][char] interpret(const(char)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  DrawInstance[][char] instances;
  State st = State(origin, orient0);
  State[] stack;
  const float a = cfg.angle;

  foreach(c; symbols) {
    switch(c) {
      case '(': stack ~= st; break;
      case ')': if(stack.length){ st = stack[$-1]; stack = stack[0 .. $-1]; } break;
      case 'X': break;
      default:
        const ax = turnAxis(c);
        if(ax != [0.0f, 0.0f, 0.0f]) { st.orient = qMul(st.orient, angleAxis(a, ax)); break; }
        if(auto br = c in cfg.brush) {
          const Matrix R = rotate(st.orient);
          instances[c] ~= DrawInstance(br.material, segmentTransform(st.pos, R, br.radius, br.length));
          if(br.advance){ st.pos = st.pos.vAdd([R[4]*br.length*0.95f, R[5]*br.length*0.95f, R[6]*br.length*0.95f]); }
        }
      break;
    }
  }
  return instances;
}
