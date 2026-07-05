/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

/** A production rule: predecessor symbol, its production string, and a weight. Rules sharing a
    predecessor should sum to 100; any shortfall is the chance the symbol is left unchanged. */
struct Rule {
  char predecessor;
  string production;
  uint probability = 100;
}

/** A stochastic L-system over plain characters. */
struct LSystem {
  char[] state;
  Rule[][char] rules;
  size_t max_length = 20000;

  /** Replace c by a weighted-random production, or keep it (no rule, or probabilities < 100). */
  const(char)[] replace(char c, ref Random rnd) {
    if(c !in rules) return [c];
    uint roll = uniform(0, 100, rnd), prev = 0;
    foreach(ref r; rules[c]) { if(roll < prev + r.probability) { return(r.production); } prev += r.probability; }
    return([c]);
  }

  /** Apply one rewrite pass over the whole state; false if the length cap is hit. */
  bool iterate(ref Random rnd) {
    if(state.length > max_length) return(false);
    char[] newstate;
    foreach(c; state) newstate ~= replace(c, rnd);
    state = newstate;
    return(true);
  }
}

/** Per-drawing-symbol spec: which material/size, and whether it advances the turtle. No Geometry here — the turtle is pure. */
struct TurtleBrush {
  int material = -1;
  float radius = 0.1f;
  float length = 1.0f;
  bool advance = true;
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];   /// per-instance tint (from the material's color)
}

/** Turtle config: per-axis turn angles (degrees) + the per-drawing-symbol brush table. */
struct TurtleConfig {
  float yaw = 25.0f;     /// + / -  spread
  float pitch = 25.0f;   /// & / ^  arch down / up
  float roll = 25.0f;    /// < / >  twist around heading
  TurtleBrush[char] brush;
}

struct TurtleState { float[3] pos; float[4] orient; }   // orient = quaternion

/** Build the throwaway trunk grammar: height Y-segments + one canopy leaf. Deterministic from seed. */
char[] buildGrammar(uint seed, uint height, string axiom, const(Rule)[] specs) {
  auto ls = LSystem(axiom.dup);
  foreach(ref r; specs) { ls.rules[r.predecessor] ~= r; }     // group productions by predecessor
  auto rnd = Random(seed | 1);
  for(uint k = 0; k < height; k++) ls.iterate(rnd);
  char[] capped;                                              // X -> trunk segment + leaf marker
  foreach(c; ls.state) { if(c == 'X'){ capped ~= 'Y'; capped ~= 'E'; } else capped ~= c; }
  ls.state = capped;
  ls.iterate(rnd);   // E -> I/B/nothing
  return ls.state;
}

/** Signed rotation axis for a turn symbol (sign folded into the axis), zeros if not a turn. */
float[3] turnAxis(char c) pure nothrow @nogc @safe {
  switch(c) {
    case '+': return [0.0f, 0.0f,  1.0f];  case '-': return [0.0f, 0.0f, -1.0f];  // yaw   (Z)
    case '&': return [1.0f, 0.0f,  0.0f];  case '^': return [-1.0f, 0.0f, 0.0f];  // pitch (X)
    case '<': return [0.0f, 1.0f,  0.0f];  case '>': return [0.0f, -1.0f, 0.0f];  // roll  (Y)
    default:  return [0.0f, 0.0f,  0.0f];
  }
}

/** Per-axis turn magnitude (degrees) for a turn symbol; 0 if not a turn. */
float turnAngle(char c, const TurtleConfig cfg) pure nothrow @nogc @safe {
  switch(c) {
    case '+': case '-': return cfg.yaw;
    case '&': case '^': return cfg.pitch;
    case '<': case '>': return cfg.roll;
    default:  return 0.0f;
  }
}
