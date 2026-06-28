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
