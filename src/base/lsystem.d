/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

enum float[3] NO_AXIS = [0.0f, 0.0f, 0.0f];     /// Axis sentinel: not a turn / use cursor frame
enum Effect : ubyte { brush, pose, asset }      /// What a content symbol does at the cursor

/** A production rule: predecessor symbol, its production string, and a weight. Rules sharing a
    predecessor should sum to 100; any shortfall is the chance the symbol is left unchanged. */
struct Rule {
  char predecessor;
  string production;
  uint probability = 100;
}

/** One alphabet entry: an effect plus its payload. Replaces TurtleBrush AND PoseBrush with a single type. */
struct Symbol {
  Effect effect = Effect.brush;
  int material = -1;                            /// brush: material index
  float radius = 0.1f;                          /// brush: half-width
  float length = 1.0f;                          /// brush: segment length
  bool advance = true;                          /// brush: move the cursor forward after drawing
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// brush: per-instance tint
  float[3] offset = [0.0f, 0.0f, 0.0f];         /// brush: local-frame draw offset [right, up, fwd]
  float depth = -1.0f;                          /// brush: Z half-extent; -1 == use radius
  char target = 0;                              /// pose: bone symbol this pose writes to
  bool bySide = false;                          /// pose: mirror by the bone's left/right sign
  float[3] axis = NO_AXIS;                      /// pose: world-axis swing; NO_AXIS == cursor swing
  string asset;                                 /// asset: external mesh/entity id (Phase 2)
  string socket;                                /// asset: named equip slot; "" == fixed graft (Phase 2)
}

/** Turtle config: per-axis turn angles (degrees) + the symbol alphabet. */
struct TurtleConfig {
  float yaw = 25.0f;     /// + / -  spread
  float pitch = 25.0f;   /// & / ^  arch down / up
  float roll = 25.0f;    /// < / >  twist around heading
  float gap = 0.2f;      /// f       move without drawing
  Symbol[char] alpha;    /// content-symbol table (brush/pose/asset)
}

struct TurtleState { float[3] pos; float[4] orient; }

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

/** Expand an axiom by 'iterations' stochastic rewrite passes; deterministic from seed. No tree/canopy logic. */
char[] expand(uint seed, uint iterations, string axiom, const(Rule)[] specs) {
  auto ls = LSystem(axiom.dup);
  foreach(ref r; specs) { ls.rules[r.predecessor] ~= r; }
  auto rnd = Random(seed | 1);
  foreach(k; 0 .. iterations) { if(!ls.iterate(rnd)) break; }
  return ls.state;
}

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
