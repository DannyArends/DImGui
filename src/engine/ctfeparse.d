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

/** CTFE: generates Resource Enum */
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

/** CTFE: generates Feature Data */
string generateFeatureData(string raw) pure {
  auto tokens = parseTokens(raw);
  string result = "immutable FeatureT[] features = [\n";
  string name = "", interaction = "";
  float noiseThreshold = 0.65f, tilePenalty = 0.0f;
  uint hs1, hs2, hmod, hrem, hmin = 1, hmax = 1;
  string[] spawnOn;
  string parts = "", drops = "";
  bool inPart = false, inDrop = false;
  // part state
  string pMesh, pRes = "None"; float pSX=1, pSXV=0, pSY=1, pSYV=0, pTaper=0, pOffY=0; bool pRepeat=false;
  // drop state
  string dMat; int dMin=1, dMax=1; bool dPerHeight=false;

  void emitPart() {
    parts ~= "    FeaturePartT(\"" ~ pMesh ~ "\", " ~
      to!string(pSX) ~ "f, " ~ to!string(pSXV) ~ "f, " ~
      to!string(pSY) ~ "f, " ~ to!string(pSYV) ~ "f, " ~
      to!string(pTaper) ~ "f, " ~ to!string(pOffY) ~ "f, " ~
      (pRepeat ? "true" : "false") ~ ", \"" ~ pRes ~ "\"),\n";
    pMesh=""; pRes="None"; pSX=1; pSXV=0; pSY=1; pSYV=0; pTaper=0; pOffY=0; pRepeat=false;
  }

  void emitDrop() {
    drops ~= "    FeatureDropT(\"" ~ dMat ~ "\", " ~
      to!string(dMin) ~ ", " ~ to!string(dMax) ~ ", " ~
      (dPerHeight ? "true" : "false") ~ "),\n";
    dMat=""; dMin=1; dMax=1; dPerHeight=false;
  }

  void emitFeature() {
    if(name == "") return;
    result ~= "  FeatureT(\"" ~ name ~ "\", [";
    foreach(s; spawnOn) result ~= "\"" ~ s ~ "\", ";
    result ~= "], " ~ to!string(noiseThreshold) ~ "f, " ~
      to!string(hs1) ~ "u, " ~ to!string(hs2) ~ "u, " ~
      to!string(hmod) ~ "u, " ~ to!string(hrem) ~ "u, " ~
      to!string(hmin) ~ "u, " ~ to!string(hmax) ~ "u, " ~
      to!string(tilePenalty) ~ "f, \"" ~ interaction ~ "\",\n" ~
      "  [\n" ~ parts ~ "  ],\n" ~
      "  [\n" ~ drops ~ "  ]),\n";
    name=""; interaction=""; spawnOn=[]; parts=""; drops="";
    noiseThreshold=0.65f; tilePenalty=0.0f;
    hs1=0; hs2=0; hmod=1; hrem=0; hmin=1; hmax=1;
  }

  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "FEATURE":       emitFeature(); name = p[1]; break;
      case "SPAWN_ON":      spawnOn ~= p[1]; break;
      case "NOISE_THRESHOLD": noiseThreshold = to!float(p[1]); break;
      case "HASH_SEED1":    hs1 = to!uint(p[1]); break;
      case "HASH_SEED2":    hs2 = to!uint(p[1]); break;
      case "HASH_MOD":      hmod = to!uint(p[1]); break;
      case "HASH_REM":      hrem = to!uint(p[1]); break;
      case "HEIGHT_MIN":    hmin = to!uint(p[1]); break;
      case "HEIGHT_MAX":    hmax = to!uint(p[1]); break;
      case "TILE_PENALTY":  tilePenalty = to!float(p[1]); break;
      case "INTERACTION":   interaction = p[1]; break;
      case "PART_BEGIN":    inPart = true; break;
      case "PART_END":      emitPart(); inPart = false; break;
      case "DROP_BEGIN":    inDrop = true; break;
      case "DROP_END":      emitDrop(); inDrop = false; break;
      case "MESH":          if(inPart) pMesh = p[1]; break;
      case "RESOURCE":      if(inPart) pRes  = p[1]; break;
      case "SCALE_X":       if(inPart) pSX   = to!float(p[1]); break;
      case "SCALE_X_VARIANCE": if(inPart) pSXV = to!float(p[1]); break;
      case "SCALE_Y":       if(inPart) pSY   = (p[1] == "tileHeight" ? -1.0f : to!float(p[1])); break;
      case "SCALE_Y_VARIANCE": if(inPart) pSYV = to!float(p[1]); break;
      case "TAPER":         if(inPart) pTaper = to!float(p[1]); break;
      case "OFFSET_Y":      if(inPart) pOffY = (p[1] == "height" ? -1.0f : to!float(p[1])); break;
      case "REPEAT":        if(inPart) pRepeat = true; break;
      case "MATERIAL":      if(inDrop) dMat = p[1]; break;
      case "DROP_MIN":      if(inDrop) dMin = to!int(p[1]); break;
      case "DROP_MAX":      if(inDrop) dMax = to!int(p[1]); break;
      case "DROP_COUNT":    if(inDrop) { dMin = to!int(p[1]); dMax = to!int(p[1]); } break;
      case "DROP_PER_HEIGHT": if(inDrop) dPerHeight = true; break;
      default: break;
    }
  }
  emitFeature();
  result ~= "];\n";
  return result;
}