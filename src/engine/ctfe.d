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

