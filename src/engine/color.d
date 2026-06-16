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

string generateColorMaps(string raw) pure {
  auto tokens = parseTokens(raw);
  string residue = "@nogc float[4] residueToColor(string r) nothrow {\n  switch(r) {\n";
  string atom = "@nogc float[4] atomToColor(string a) nothrow {\n  switch(a) {\n";
  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length != 3) continue;
    if(p[0] == "RESIDUE") residue ~= format("    case \"%s\": return Colors.%s;\n", p[1], p[2]);
    if(p[0] == "ATOM") atom ~= format("    case \"%s\": return Colors.%s;\n", p[1], p[2]);
  }
  string tail = "    default: return Colors.white;\n  }\n}\n";
  return(residue ~ tail ~ atom ~ tail);
}

mixin(generateColorsEnum(import("data/raws/colors.txt")));
mixin(generateColorMaps(import("data/raws/colors.txt")));

/** Generate a random color */
float[4] randomColor(float alpha = 1.0f) { return([uniform(0.0f, 1.0f), uniform(0.0f, 1.0f), uniform(0.0f, 1.0f), alpha]); }

