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