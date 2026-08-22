/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import matrix : degree;

enum float[3] NO_AXIS = [0.0f, 0.0f, 0.0f];     /// Axis sentinel: not a turn / use cursor frame
enum Effect : ubyte { bone, brush, pose }       /// bone: skeleton node (mesh optional), brush: leaf draw, pose
enum string RESERVED = "()~%|+-&^<>@";

/** A production rule: predecessor, production, weight, and the window [nMin, nMax) on the matched
    module's own parameter n that the rule is active in (int.min/int.max = open bound). */
struct Rule {
  string predecessor;                           /// symbol this rule rewrites
  string production;                            /// replacement string
  uint probability = 100;                       /// weight among the predecessor's active rules (shortfall = passthrough)
  int nMin = int.min;                           /// window low on the module's own parameter (inclusive); int.min = open
  int nMax = int.max;                           /// window high (exclusive); int.max = open
}

/** One L-system token: a module name and an optional integer parameter (NONE = bare, e.g. a glyph or plain brush).
 * TODO: add @{x,y,z} walk-to-point glyph (engine-side `solve` into current frame) to replace hand-solved &{θ}+{φ}~{d} */
struct LSym {
  enum int NONE = int.min;   /// sentinel: no parameter
  string name;               /// module name or single glyph
  int n = NONE;              /// integer parameter (growth); NONE => bare
  float arg = float.nan;     /// float parameter (turn angle / move distance); NaN => config default
  @property bool hasN() const pure nothrow @nogc @safe { return n != NONE; }
  @property bool hasArg() const pure nothrow @nogc @safe { return arg == arg; }
}

/** One alphabet entry: an effect plus its payload. Replaces TurtleBrush AND PoseBrush with a single type. */
struct Symbol {
  Effect effect = Effect.brush;
  int material = -1;                            /// brush: material index
  float[3] size = [0.1f, 1.0f, 0.1f];           /// brush: local half-extents [radius(X), length(Y), depth(Z)]
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// brush: per-instance tint
  float[3] offset = [0.0f, 0.0f, 0.0f];         /// brush: local-frame draw offset [right, up, fwd]
  float taper = 0.0f;                           /// brush: radius growth per unit of the module's parameter n (0 = uniform)
  string target = "";                           /// pose: bone symbol this pose writes to
}

/** Turtle config: per-axis turn angles (degrees) + the symbol alphabet. */
struct TurtleConfig {
  float yaw = 90.0f;        /// + / -  spread
  float pitch = 90.0f;      /// & / ^  arch down / up
  float roll = 90.0f;       /// < / >  twist around heading
  float gap = 1.0f;         /// ~       move without drawing
  Symbol[string] alpha;     /// content-symbol table (brush/pose/asset)
}

/** A stochastic L-system over plain characters. */
struct LSystem {
  LSym[] state;
  Rule[][string] rules;
  size_t max_length = 20000;

  /** Replace c by a weighted-random production, or keep it. */
  pure LSym[] replace(LSym c, ref Random rnd) {
    if(c.name !in rules) return [c];
    uint roll = uniform(0, 100, rnd), prev = 0;
    foreach(ref r; rules[c.name]) {
      if(!active(r, c)) continue;
      if(roll < prev + r.probability) return(expand(r.production, c.n));
      prev += r.probability;
    }
    return([c]);
  }

  /** Apply one rewrite pass; false if the length cap is hit. */
  pure bool iterate(ref Random rnd) {
    if(state.length > max_length) return(false);
    LSym[] newstate;
    foreach(c; state) { newstate ~= replace(c, rnd); }
    state = newstate;
    return(true);
  }
}

/** Evaluate a parameter expression against the matched n: "n", "n-k", "n+k", or a literal. */
pure int evalExpr(const(char)[] e, int n) {
  if(e.length && e[0] == 'n') return (e.length == 1) ? n : (e[1] == '-' ? n - e[2 .. $].to!int : n + e[2 .. $].to!int);
  return e.to!int;
}

/** Substitute n into every {expr} of a production/axiom, then tokenise. */
pure LSym[] expand(const(char)[] s, int n) {
  char[] outp; size_t i = 0;
  while(i < s.length) {
    if(s[i] == '@' && i + 1 < s.length && s[i + 1] == '{') {          // @{x;y;z} -> &{θ}+{φ}~{d}
      size_t k = i + 2; while(k < s.length && s[k] != '}') { k++; }
      auto p = s[i + 2 .. k].split(";");
      immutable float x = p[0].to!float, y = p[1].to!float, z = p[2].to!float;
      immutable float th = degree(atan2(z, y));
      immutable float ph = degree(atan2(-x, sqrt(y*y + z*z)));
      immutable float d = sqrt(x*x + y*y + z*z);
      outp ~= ("&{" ~ th.to!string ~ "}+{" ~ ph.to!string ~ "}~{" ~ d.to!string ~ "}").dup;
      i = k + 1;
    } else if(s[i] == '{' && !(i > 0 && "+-&^<>~".canFind(s[i - 1]))) {
      size_t k = i + 1; 
      while(k < s.length && s[k] != '}') { k++; }
      outp ~= '{' ~ evalExpr(s[i + 1 .. k], n).to!string ~ '}'; i = k + 1;
    } else { outp ~= s[i]; i++; }
  }
  return lex(outp);
}

/** Tokenise an axiom/production: each reserved glyph is one token, each maximal run of non-reserved
    non-space chars is one module name; whitespace separates and is dropped. */
pure LSym[] lex(const(char)[] s) {
  LSym[] toks; size_t i = 0;
  while(i < s.length) {
    immutable char c = s[i];
    if(c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
    if(RESERVED.canFind(c)) {
      LSym g = { name: [c].idup }; size_t j = i + 1;
      if(j < s.length && s[j] == '{' && "+-&^<>~".canFind(c)) {   // parametric turn/step: {angle} or {distance}
        size_t k = j + 1; while(k < s.length && s[k] != '}') k++;
        g.arg = s[j + 1 .. k].to!float; j = k + 1;
      } else if(j < s.length && s[j] == '{' && c == '@') {         // @{x;y;z}: consume the group (expanded elsewhere)
        size_t k = j + 1; while(k < s.length && s[k] != '}') k++;
        j = k + 1;
      }
      toks ~= g; i = j; continue;
    }
    size_t j = i; while(j < s.length && s[j] != ' ' && s[j] != '{' && !RESERVED.canFind(s[j])) j++;
    LSym t = { name: s[i .. j].idup };
    if(j < s.length && s[j] == '{') {
      size_t k = j + 1; while(k < s.length && s[k] != '}'){ k++; }
      auto inner = s[j + 1 .. k];
      if(inner.length && inner.all!(ch => ch >= '0' && ch <= '9')) t.n = inner.to!int;
      j = k + 1;
    }
    toks ~= t; i = j;
  }
  return(toks);
}

/** Is rule r active for this token; i.e. its parameter n falls in the rule's [nMin, nMax) window? */
@nogc pure bool active(ref const Rule r, LSym tok) nothrow { return r.nMin <= tok.n && tok.n < r.nMax; }

/** Any symbol in 's' carrying an active rule ? */
@nogc pure bool anyActive(const(LSym)[] s, const Rule[][string] rules) nothrow {
  foreach(c; s) { if(auto rs = c.name in rules) {
    foreach(ref r; *rs) { if(active(r, c)) { return(true); } }
  } }
  return(false);
}

/** Grow an axiom to a fixed point: repeatedly rewrite, each rule gated by the [nMin, nMax) window on the
    matched module's own parameter n (the axiom seeds the initial n), until no rule matches. Deterministic from seed.
    One builder for vegetation, entities, and clip time-walks — the cap is data (a rule), not a phase. */
pure LSym[] grammar(uint seed, int size, string axiom, const(Rule)[] rules, int safety = 1024) {
  auto ls = LSystem(expand(axiom, size));
  foreach(ref r; rules) { ls.rules[r.predecessor] ~= r; }
  auto rnd = Random(seed | 1);
  for(int i = 0; i < safety; i++) {
    if(!anyActive(ls.state, ls.rules)) break;   // fixed point: nothing left to rewrite
    if(!ls.iterate(rnd)) break;                 // length cap
  }
  return ls.state;
}

/** Signed rotation axis for a turn symbol (sign folded into the axis), zeros if not a turn. */
@nogc pure float[3] turnAxis(char c) nothrow {
  switch(c) {
    case '+': return [0.0f, 0.0f,  1.0f];  case '-': return [0.0f, 0.0f, -1.0f];  // yaw   (Z)
    case '&': return [1.0f, 0.0f,  0.0f];  case '^': return [-1.0f, 0.0f, 0.0f];  // pitch (X)
    case '<': return [0.0f, 1.0f,  0.0f];  case '>': return [0.0f, -1.0f, 0.0f];  // roll  (Y)
    default:  return NO_AXIS;
  }
}

/** Per-axis turn magnitude (degrees) for a turn symbol; 0 if not a turn. */
@nogc pure float turnAngle(char c, const TurtleConfig cfg) nothrow {
  switch(c) {
    case '+': case '-': return cfg.yaw;
    case '&': case '^': return cfg.pitch;
    case '<': case '>': return cfg.roll;
    default:  return 0.0f;
  }
}
