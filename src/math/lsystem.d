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
Symbol[] buildGrammar(uint seed, uint height, string axiom, const(char)[] preds, const(string)[] prods, const(uint)[] probs) {
  Symbol[] start;
  foreach(c; axiom){ start ~= Symbol(c); }
  auto ls = LSystem(start);
  foreach(i; 0 .. preds.length) {                        // group productions by predecessor
    auto key = Symbol(preds[i]);
    if(key !in ls.rules){ ls.rules[key] = Rules([]); }
    ls.rules[key].rules ~= Rule(prods[i], cast(size_t)probs[i]);
  }
  auto rnd = Random(seed | 1);
  for(uint k = 0; k < height; k++) ls.iterate(rnd);
  foreach(ref s; ls.state) if(s == Symbols.Axiom) s = Symbols.End;  // force open tips to cap-point
  ls.iterate(rnd);      
  return ls.state;
}
