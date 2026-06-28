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
  bool opEquals(const Symbol s) const { return symbol == s.symbol; }
  size_t toHash() const @safe nothrow { return symbol; }
}

enum Symbols : Symbol {
  Axiom = Symbol('X', false),
  End = Symbol('E', false),
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
  Push = Symbol('('), Pop = Symbol(')')
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

/** Flat production spec passed across the math/game boundary. */
struct RuleSpec { char pred; string prod; uint prob = 100; }

/** Lsystem */
struct LSystem {
  Symbol[] state;
  Rule[][Symbol] rules;
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
char[] buildGrammar(uint seed, uint height, string axiom, const(RuleSpec)[] specs) {
  Symbol[] start;
  foreach(c; axiom){ start ~= Symbol(c); }
  auto ls = LSystem(start);
  foreach(ref s; specs) { ls.rules[Symbol(s.pred)] ~= Rule(s.prod, cast(size_t)s.prob); }
  auto rnd = Random(seed | 1);
  for(uint k = 0; k < height; k++) ls.iterate(rnd);
  Symbol[] capped;
  foreach(s; ls.state) { if(s == Symbols.Axiom){ capped ~= Symbols.Cylinder; capped ~= Symbols.End; } else capped ~= s; }
  ls.state = capped;
  ls.iterate(rnd);   // E -> I/B/nothing
  return ls.state.map!(s => s.symbol).array;
}
