/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

/** Symbol */
struct Symbol {
  char symbol;
  bool constant = true;
  alias symbol this;
}

enum Symbols : Symbol {
  Axiom = Symbol('X', false),
  // Drawing symbols
  Cone = Symbol('C'),
  Cylinder = Symbol('Y'),
  Cube = Symbol('B'),
  Icosa = Symbol('I'),
  Sphere = Symbol('S'),
  Torus = Symbol('T'),
  // Movement
  YawPos = Symbol('+'), YawNeg = Symbol('-'),
  PitchDn = Symbol('&'), PitchUp = Symbol('^'),
  RollPos = Symbol('<'), RollNeg = Symbol('>'),
  Push = Symbol('['), Pop = Symbol(']')
}

/** Production Rule */
struct Rule {
  Symbol[] production;
  size_t probability;

  this(string p, size_t prob = 100) {
    foreach (char c; p) { production ~= Symbol(c); }
    probability = prob;
  }
}

/** A list of production rules */
struct Rules {
  Rule[] rules;
  alias rules this;
}

/** Lsystem */
struct LSystem {
  Symbol[] state;
  Rules[Symbol] rules;
  size_t max_length = 20000;

  /** If any rule matches, return the production, otherwise return the symbol */
  Symbol[] replace(Symbol s, ref Random rnd) {
    if(s !in rules) return([s]);
    size_t p = uniform(0, 100, rnd);
    size_t prev = 0;
    for (size_t i = 0; i < rules[s].length; i++) {
      if( p < (prev + rules[s][i].probability) ) return rules[s][i].production;
      prev += rules[s][i].probability;
    }
    if(s.constant) return([s]);
    return([]);
  }

  bool iterate(ref Random rnd) {
    if(state.length > max_length) return(false);
    Symbol[] newstate;
    newstate.reserve(state.length);
    for (size_t i = 0; i < state.length; i++) { newstate ~= replace(state[i], rnd); }
    state = newstate;
    return(true);
  }
}

/** Build the throwaway trunk grammar: height Y-segments + one canopy leaf. Deterministic from seed. */
Symbol[] buildGrammar(uint seed, uint height) {
  auto ls = LSystem([Symbols.Axiom]);                    // X
  ls.rules[Symbols.Axiom] = Rules([ Rule("YX", 100) ]);  // X -> Y X  (grow trunk)
  auto rnd = Random(seed | 1);
  for(uint i = 0; i < height; i++) ls.iterate(rnd);      // -> Y*height X
  // terminate: replace trailing X (Axiom) with canopy leaf I
  if(ls.state.length && ls.state[$-1] == Symbols.Axiom) ls.state[$-1] = Symbols.Icosa;
  return ls.state;                                        // "YYYY...I"
}
