/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

enum float[3] NO_AXIS = [0.0f, 0.0f, 0.0f];     /// Axis sentinel: not a turn / use cursor frame
enum Effect : ubyte { brush, pose, asset }      /// What a content symbol does at the cursor
enum int GEN_END = int.min;

/** A production rule: predecessor, production, weight, and the generation window [genMin, genMax) it's
    active in. GEN_END in a bound means "the growth budget", so a cap is just a rule opened at the budget. */
struct Rule {
  char predecessor;                             /// symbol this rule rewrites
  string production;                            /// replacement string
  uint probability = 100;                       /// weight among the predecessor's active rules (shortfall = passthrough)
  int genMin = 0;                               /// first generation active (GEN_END => budget)
  int genMax = int.max;                         /// one past last active generation (GEN_END => budget)
}

/** Is rule r active at generation t, given the growth budget? */
bool active(ref const Rule r, int t, int budget) pure nothrow @nogc @safe {
  immutable int lo = (r.genMin == GEN_END) ? budget : r.genMin;
  immutable int hi = (r.genMax == GEN_END) ? budget : r.genMax;
  return lo <= t && t < hi;
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

  /** Replace c by a weighted-random production active at generation t, or keep it. */
  const(char)[] replace(char c, ref Random rnd, int t, int budget) {
    if(c !in rules) return [c];
    uint roll = uniform(0, 100, rnd), prev = 0;
    foreach(ref r; rules[c]) {
      if(!active(r, t, budget)) continue;
      if(roll < prev + r.probability) { return(r.production); }
      prev += r.probability;
    }
    return([c]);
  }

  /** Apply one rewrite pass at generation t; false if the length cap is hit. */
  bool iterate(ref Random rnd, int t, int budget) {
    if(state.length > max_length) return(false);
    char[] newstate;
    foreach(c; state) newstate ~= replace(c, rnd, t, budget);
    state = newstate;
    return(true);
  }
}

/** Any symbol in `s` carrying a rule active at generation t? */
bool anyActive(const(char)[] s, const Rule[][char] rules, int t, int budget) {
  foreach(c; s) { if(auto rs = c in rules) {
    foreach(ref r; *rs) { if(active(r, t, budget)) { return(true); } }
  } }
  return(false);
}

/** Grow an axiom to a fixed point: each generation applies the rules active at that generation (growth rules
    windowed [0, budget), caps opened at the budget), until no active rule remains. Deterministic from seed.
    One builder for vegetation, entities, and clip time-walks — the cap is data (a rule), not a phase. */
char[] grammar(uint seed, int budget, string axiom, const(Rule)[] rules, int safety = 1024) {
  auto ls = LSystem(axiom.dup);
  foreach(ref r; rules) { ls.rules[r.predecessor] ~= r; }
  auto rnd = Random(seed | 1);
  for(int t = 0; t < safety; t++) {
    if(!anyActive(ls.state, ls.rules, t, budget)) break;   // fixed point: nothing left to rewrite
    if(!ls.iterate(rnd, t, budget)) break;                 // length cap
  }
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
