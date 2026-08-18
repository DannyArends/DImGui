/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import ctfe : parseTokens, splitColon;
import quaternion: w;
import vector : x,y,z;

@nogc pure ImVec4 asIm(T)(const T[4] v) nothrow { return(ImVec4(v.x, v.y, v.z, v.w)); }

/** CTFE: generate Colors enum from raws text */
string generateColorsEnum(string raw) pure {
  auto tokens = parseTokens(raw);
  string result = "enum Colors : float[4] {\n";
  string current = "";
  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    if(p[0] == "COLOR" && p.length == 2) { current = p[1]; }
    else if(p[0] == "RGB" && p.length == 4 && current != ""){ result ~= format("  %s = [%sf, %sf, %sf, 1.0f],\n", current, p[1], p[2], p[3]); }
  }
  return result ~ "}\n";
}

mixin(generateColorsEnum(import("data/raws/colors.txt")));

/** Generate a random color */
float[4] randomColor(float alpha = 1.0f) {
  enum n = EnumMembers!Colors.length;
  const i = uniform(0, n);
  static foreach(j, m; EnumMembers!Colors) if(j == i) return cast(float[4])m;
  return Colors.white;
}

/** CTFE: resolve a Colors member by name, defaults to white. */
Colors toColor(string name) pure {
  static foreach(m; __traits(allMembers, Colors)) if(name == m) return __traits(getMember, Colors, m);
  return Colors.white;
}

enum Colors[] colorPalette = [EnumMembers!Colors];

/** Nearest palette ordinal to a color (squared-distance over RGB). */
@nogc uint paletteOrdinal(const float[4] c) nothrow {
  uint best = 0;
  float bestD = float.max;
  static foreach(i, m; EnumMembers!Colors) {{
    const float[4] p = cast(float[4])m;
    const float dr = c[0]-p[0], dg = c[1]-p[1], db = c[2]-p[2];
    const float d = dr*dr + dg*dg + db*db;
    if(d < bestD) { bestD = d; best = cast(uint)i; }
  }}
  return best;
}