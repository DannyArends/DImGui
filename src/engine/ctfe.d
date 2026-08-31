/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

/** True iff T holds no GC-scannable pointers — safe to store in NO_SCAN memory. */
enum bool isPod(T) = !hasIndirections!T;

/** Compile-time POD gate */
template Pod(T) {
  static assert(isPod!T, "Type `" ~ T.stringof ~ "` contains GC-traced indirections ");
  alias Pod = T;
}

/** CTFE: split string into tokens between [ and ] */
string[] parseTokens(string s) pure {
  string[] tokens;
  size_t i = 0;
  while(i < s.length) {
    if(s[i] == '[') {
      size_t j = i + 1;
      while(j < s.length && s[j] != ']') j++;
      tokens ~= s[i+1..j];
      i = j + 1;
    } else { i++; }
  }
  return tokens;
}

/** CTFE: split token on ':' */
string[] splitColon(string s) pure {
  string[] parts;
  size_t start = 0;
  for(size_t i = 0; i <= s.length; i++) { if(i == s.length || s[i] == ':') { parts ~= s[start..i]; start = i + 1; } }
  return parts;
}

/** CTFE: emit 'enum <name> : ubyte { [sentinel,] one member per [tag:member] }'. */
string enumFromTag(string raw, string tag, string name, string sentinel = "") pure {
  string result = "enum " ~ name ~ " : ubyte {\n";
  if(sentinel.length) result ~= "  " ~ sentinel ~ ",\n";
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length >= 2 && p[0] == tag) result ~= "  " ~ p[1] ~ ",\n";
  }
  return result ~ "}\n";
}

/** CTFE: Optional positional token field parsed to T (default string); `def` if absent/empty. */
T opt(T = string)(const string[] p, size_t i, T def = T.init) pure {
  return i < p.length && p[i].length ? p[i].to!T : def;
}

/** CTFE: value of the `key=...` part among token fields, or `def` if absent. */
string namedField(const string[] p, string key, string def = "") pure {
  foreach(kv; p){ if(kv.length > key.length + 1 && kv[0 .. key.length] == key && kv[key.length] == '=') {
    return kv[key.length + 1 .. $];
  } }
  return def;
}

/** One member-emission rule for composedEnum.
 *  Plain:   groupTag=="" -> every [tag:x] emits member x (field-th token).
 *  Grouped: [groupTag:g] sets the prefix; every [tag:...] emits g ~ (field-th token). */
struct EnumRule { string tag; string groupTag = ""; int field = 1; string key = ""; }

/** Generic CTFE enum codegen: scan raws in order, emit `enum name : ubyte { sentinel, members... }`.
 *  Members are deduped; the sentinel (e.g. "None") is skipped if a rule would re-emit it. Game-unaware. */
string composedEnum(string name, string sentinel, EnumRule[] rules, string[] raws...) pure {
  string[] members; bool[string] seen; string prefix;
  foreach(raw; raws) foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length < 2) continue;
    foreach(r; rules) {
      if(r.groupTag.length && p[0] == r.groupTag) prefix = p[1];
      else if(p[0] == r.tag) {
        immutable string val = r.key.length ? namedField(p, r.key) : (p.length > r.field ? p[r.field] : "");
        if(val.length == 0) continue;
        immutable string m = (r.groupTag.length ? prefix : "") ~ val;
        if(m != sentinel && m !in seen) { seen[m] = true; members ~= m; }
      }
    }
  }
  string s = "enum " ~ name ~ " : ubyte {\n";
  if(sentinel.length) s ~= "  " ~ sentinel ~ ",\n";
  foreach(m; members) s ~= "  " ~ m ~ ",\n";
  return s ~ "}\n";
}

/** Generic block-list parser: `[blockTag:name]` starts a record; `handler` fills fields. seedNone prepends index-0 None. */
T[] parseRawsGeneric(T, string blockTag, alias handler)(string raw, bool seedNone = false) pure {
  T[] items; if(seedNone) items ~= T.init;   // index 0 == None, for enum-parallel tables (ItemTemplate/ResourceType)
  T cur; bool inBlock;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    if(p[0] == blockTag) { if(inBlock) items ~= cur; cur = T.init; cur.name = p[1]; inBlock = true; continue; }
    if(inBlock) handler(cur, p);
  }
  if(inBlock) items ~= cur;
  return items;
}

unittest {
  // parseTokens: extracts bracketed groups, ignores text between/outside brackets
  static assert(parseTokens("[a][b][c]") == ["a", "b", "c"]);
  static assert(parseTokens("x[tag:v]y[k:w]") == ["tag:v", "k:w"]);
  static assert(parseTokens("no brackets here") == []);
  static assert(parseTokens("[unclosed") == ["unclosed"]);   // runs to end if no ']'
  static assert(parseTokens("") == []);

  // splitColon: splits on ':', preserves empties, never drops trailing
  static assert(splitColon("a:b:c") == ["a", "b", "c"]);
  static assert(splitColon("solo") == ["solo"]);
  static assert(splitColon("a::b") == ["a", "", "b"]);        // empty middle field
  static assert(splitColon("trailing:") == ["trailing", ""]);
  static assert(splitColon("") == [""]);

  // opt: positional field with default fallback
  static assert(opt(["x", "y", "z"], 1) == "y");
  static assert(opt(["x"], 5, "def") == "def");              // index out of range -> default
  static assert(opt(["x", ""], 1, "def") == "def");          // empty field -> default
  static assert(opt!int(["10", "20"], 0) == 10);             // typed parse
  static assert(opt!int([], 0, 99) == 99);                   // empty list -> default

  // namedField: finds key=value among fields
  static assert(namedField(["a=1", "b=2"], "b") == "2");
  static assert(namedField(["a=1"], "missing", "d") == "d"); // absent -> default
  static assert(namedField(["ab=1"], "a") == "");            // "ab" must not match key "a"
  static assert(namedField(["a=x=y"], "a") == "x=y");        // value may contain '='

  // enumFromTag: emits an enum body from matching [tag:member] tokens
  static assert(enumFromTag("[K:Alpha][K:Beta][OTHER:Zed]", "K", "Letters", "None") == "enum Letters : ubyte {\n  None,\n  Alpha,\n  Beta,\n}\n");
  static assert(enumFromTag("[K:X]", "K", "E") == "enum E : ubyte {\n  X,\n}\n");

  // composedEnum: plain rule dedups members, skips sentinel
  static assert(composedEnum("Res", "None", [EnumRule("R")], "[R:Iron][R:Gold][R:Iron]") == "enum Res : ubyte {\n  None,\n  Iron,\n  Gold,\n}\n");
  // composedEnum: grouped rule prefixes members with the group value
  static assert(composedEnum("Job", "", [EnumRule("J", "GRP")], "[GRP:Mine][J:Coal][J:Iron]") == "enum Job : ubyte {\n  MineCoal,\n  MineIron,\n}\n");
}
