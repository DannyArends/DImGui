/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

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

/**  CTFE: split token on ':' */
string[] splitColon(string s) pure {
  string[] parts;
  size_t start = 0;
  for(size_t i = 0; i <= s.length; i++) {
    if(i == s.length || s[i] == ':') { parts ~= s[start..i]; start = i + 1; }
  }
  return parts;
}

/** CTFE: generate Colors enum from raws text */
string generateColorsEnum(string raw) pure {
  auto tokens = parseTokens(raw);
  string result = "enum Colors : float[4] {\n";
  string current = "";
  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    if(p[0] == "COLOR" && p.length == 2) { current = p[1]; }
    else if(p[0] == "RGB" && p.length == 4 && current != "") {
      result ~= "  " ~ current ~ " = [" ~ p[1] ~ "f, " ~ p[2] ~ "f, " ~ p[3] ~ "f, 1.0f],\n";
    }
  }
  result ~= "}\n";
  return result;
}

/** CTFE: generates heightToResource function */
string generateHeightToResource(string raw) pure {
  auto tokens = parseTokens(raw);
  string result = "@nogc pure ResourceType heightToResource(float h, float t) nothrow {\n";
  string lo = "", hi = "";
  string[] results;
  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    if(p[0] == "HEIGHT_RULE" && p.length == 3) {
      if(lo != "" && results.length > 0) {
        result ~= "  if(h < " ~ hi ~ "f) { ResourceType[" ~ to!string(results.length) ~ "] v = [";
        foreach(i, r; results) { result ~= "ResourceType." ~ r ~ (i+1 < results.length ? ", " : ""); }
        result ~= "]; return v[cast(uint)(t * " ~ to!string(results.length) ~ ") % " ~ to!string(results.length) ~ "]; }\n";
      }
      lo = p[1]; hi = p[2]; results = [];
    } else if(p[0] == "RESULT" && p.length == 2) { results ~= p[1]; }
  }
  if(results.length > 0) { result ~= "  return ResourceType." ~ results[0] ~ ";\n"; } // emit last rule
  result ~= "}\n";
  return result;
}

string generateResourceEnum(string raw) pure {
  auto tokens = parseTokens(raw);
  string enumResult  = "enum ResourceType : ubyte {\n";
  string switchResult = "@nogc pure ResourceT resourceData(ResourceType rt) nothrow {\n  final switch(rt) {\n";
  string current = "";
  string texture = "None", mesh = "Blocks", color = "Colors.white";
  bool traversable = false, buildable = false;
  ubyte maxStack = 1;
  float cost = 0.0f, scale = 1.0f;

  void emitCurrent() {
    if(current == "") return;
    enumResult  ~= "  " ~ current ~ ",\n";
    switchResult ~= "    case ResourceType." ~ current ~ ": " ~
      "return ResourceT(\"" ~ texture ~ "\", " ~
      (traversable ? "true" : "false") ~ ", " ~
      (buildable   ? "true" : "false") ~ ", " ~
      to!string(cast(int)maxStack) ~ ", " ~
      to!string(cost) ~ "f, \"" ~ mesh ~ "\", " ~
      to!string(scale) ~ "f, " ~ color ~ ");\n";
  }

  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "MATERIAL":
        emitCurrent();
        current = p[1]; texture = p[1]; mesh = "Blocks"; color = "Colors.white";
        traversable = false; buildable = false; maxStack = 1; cost = 0.0f; scale = 1.0f;
        break;
      case "TEXTURE": texture = p[1]; break;
      case "TRAVERSABLE": traversable = true; break;
      case "BUILDABLE": buildable = true; break;
      case "MESH": mesh = p[1]; break;
      case "SCALE": scale = to!float(p[1]); break;
      case "COST": cost = to!float(p[1]); break;
      case "MAX_STACK": maxStack = cast(ubyte)to!int(p[1]); break;
      case "COLOR": color = "Colors." ~ p[1]; break;
      default: break;
    }
  }
  emitCurrent();
  enumResult  ~= "}\n";
  switchResult ~= "  }\n}\n";
  return enumResult ~ switchResult;
}