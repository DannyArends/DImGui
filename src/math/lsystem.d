/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Symbol
 */
struct Symbol {
  char symbol;
  bool constant = true;
  alias symbol this;
}

enum Symbols : Symbol {
  Origin = Symbol('O'),
  Point = Symbol('.'),
  Move = Symbol('M'),
  Rotate = Symbol('R'),
  PushLoc = Symbol('<'),
  PopLoc = Symbol('>'),
  Numeric = Symbol('N'),
  Float = Symbol('F'),
  Faster = Symbol('+'),
  Slower = Symbol('-'),
  Color = Symbol('C'),
  Forward = Symbol('W'),
  Backward = Symbol('S'),
  Left = Symbol('A'),
  Right = Symbol('D'),
  Up = Symbol('X'),
  Down = Symbol('Z')
}

/** Production Rule
 */
struct Rule {
  Symbol[] production;
  size_t probability;

  this(string p, size_t prob = 100) {
    foreach (char c; p) {
      production ~= Symbol(c);
    }
    probability = prob;
  }
}

/** A list of production rules
 */
struct Rules {
  Rule[] rules;
  alias rules this;
}

struct LSystem {
  Symbol[] state;
  Rules[Symbol] rules;
  size_t max_length = 20000;

  // If any rule matches, return the production, otherwise return the symbol
  Symbol[] replace(Symbol s) {
    size_t p = uniform(0, 100);
    size_t prev = 0;
    if(s !in rules) return([s]);
    for (size_t i = 0; i < rules[s].length; i++) {
      if( p < (prev + rules[s][i].probability) ) return rules[s][i].production;
      prev += rules[s][i].probability;
    }
    if(s.constant) return([s]);
    return([]);
  }

  bool iterate() {
    Symbol[] newstate;
    if(state.length > max_length) return(false);
    for (size_t i = 0; i < state.length; i++) {
      newstate ~= replace(state[i]);
    }
    if(newstate.length == 0) newstate ~= Symbols.Origin;
    state = newstate;
    return(true);
  }

}

LSystem createLSystem() {
  auto test = LSystem([Symbols.Origin]);
  test.rules[Symbols.Origin] = Rules([Rule("W.O", 5)]);
  test.rules[Symbols.Origin] ~= Rule("S.O", 5);
  test.rules[Symbols.Origin] ~= Rule("A.O", 5);
  test.rules[Symbols.Origin] ~= Rule("D.O", 5);
  test.rules[Symbols.Origin] ~= Rule("X.O", 5);
  test.rules[Symbols.Origin] ~= Rule("Z.O", 5);
  test.rules[Symbols.Origin] ~= Rule("MC.O", 5);
  test.rules[Symbols.Origin] ~= Rule("R.O", 5);
  test.rules[Symbols.Origin] ~= Rule("<O", 15);
  test.rules[Symbols.Origin] ~= Rule(">O", 15);

  foreach (s; [Symbols.Forward, Symbols.Backward, 
               Symbols.Left, Symbols.Right, 
               Symbols.Up, Symbols.Down] ) {
   // test.rules[s] ~= Rule("O", 1);  // Super Speed, Ball Like
   // test.rules[s] ~= Rule("RM", 3);
  }

  for(size_t i = 0; i < 5; i++){
    //SDL_Log("state: %s", to!string(test.state).toStringz);
    test.iterate();
  }
  return(test);
}
