/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import ctfe : parseTokens, splitColon;

/** NOTE: changes to .txt files require: dub build --force
 * import() is resolved at compile-time; dub does not track these as dependencies */
mixin(generateResourceEnum(import("data/raws/materials.txt")));
mixin(generateHeightToResource(import("data/raws/terrain.txt")));
mixin(generateFeatureData(import("data/raws/features.txt")));

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
      if(lo != "" && results.length > 0)
        result ~= format("  if(h < %sf) { ResourceType[%s] v = [%s]; return v[cast(uint)(t * %s) %% %s]; }\n",
          hi, results.length, results.map!(r => "ResourceType." ~ r).join(", "), results.length, results.length);
      lo = p[1]; hi = p[2]; results = [];
    } else if(p[0] == "RESULT" && p.length == 2) { results ~= p[1]; }
  }
  if(results.length > 0) result ~= format("  return ResourceType.%s;\n", results[0]);
  return result ~ "}\n";
}

/** CTFE: generates ResourceType enum and resourceData function */
string generateResourceEnum(string raw) pure {
  auto tokens = parseTokens(raw);
  string enumResult   = "enum ResourceType : ubyte {\n";
  string switchResult = "@nogc pure ResourceT resourceData(ResourceType rt) nothrow {\n  final switch(rt) {\n";
  string current = "", texture = "None", mesh = "Blocks", color = "Colors.white";
  bool traversable = false, buildable = false;
  ubyte maxStack = 1;
  float cost = 0.0f, scale = 1.0f;

  void emitCurrent() {
    if(current == "") return;
    enumResult  ~= format("  %s,\n", current);
    switchResult ~= format("    case ResourceType.%s: return ResourceT(\"%s\", %s, %s, %s, %sf, \"%s\", %sf, %s);\n",
      current, texture, traversable, buildable, maxStack, cost, mesh, scale, color);
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
  return enumResult ~ "}\n" ~ switchResult ~ "  }\n}\n";
}

/** CTFE: generates immutable FeatureT[] features */
string generateFeatureData(string raw) pure {
  auto tokens = parseTokens(raw);
  string result = "immutable FeatureT[] features = [\n";
  string name = "", interaction = "";
  float noiseThreshold = 0.65f, tilePenalty = 0.0f, progressRate = 0.25f;
  uint hs1, hs2, hmod, hrem, hmin = 1, hmax = 1;
  string[] spawnOn;
  string parts = "", drops = "";
  string pMesh, pRes = "None"; float pSX=1, pSXV=0, pSY=1, pSYV=0, pTaper=0, pOffY=0; bool pRepeat=false;
  string dMat; int dMin=1, dMax=1; bool dPerHeight=false;

  void emitPart() {
    if(pMesh == "") return;
    parts ~= format("    FeaturePartT(\"%s\", %sf, %sf, %sf, %sf, %sf, %sf, %s, \"%s\"),\n",
      pMesh, pSX, pSXV, pSY, pSYV, pTaper, pOffY, pRepeat, pRes);
    pMesh=""; pRes="None"; pSX=1; pSXV=0; pSY=1; pSYV=0; pTaper=0; pOffY=0; pRepeat=false;
  }

  void emitDrop() {
    if(dMat == "") return;
    drops ~= format("    FeatureDropT(\"%s\", %s, %s, %s),\n", dMat, dMin, dMax, dPerHeight);
    dMat=""; dMin=1; dMax=1; dPerHeight=false;
  }

  void emitFeature() {
    if(name == "") return;
    string spawnList = spawnOn.map!(s => format("\"%s\"", s)).join(", ");
    result ~= format("  FeatureT(\"%s\", [%s], %sf, %su, %su, %su, %su, %su, %su, %sf, %sf, \"%s\",\n  [\n%s  ],\n  [\n%s  ]),\n",
      name, spawnList, noiseThreshold, hs1, hs2, hmod, hrem, hmin, hmax, tilePenalty, progressRate, interaction, parts, drops);
    name=""; interaction=""; spawnOn=[]; parts=""; drops="";
    noiseThreshold=0.65f; tilePenalty=0.0f; progressRate=0.25f;
    hs1=0; hs2=0; hmod=1; hrem=0; hmin=1; hmax=1;
  }

  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "FEATURE": emitFeature(); name = p[1]; break;
      case "SPAWN_ON": spawnOn ~= p[1]; break;
      case "NOISE_THRESHOLD":  noiseThreshold  = to!float(p[1]); break;
      case "HASH_SEED1": hs1 = to!uint(p[1]); break;
      case "HASH_SEED2": hs2 = to!uint(p[1]); break;
      case "HASH_MOD": hmod = to!uint(p[1]); break;
      case "HASH_REM": hrem = to!uint(p[1]); break;
      case "HEIGHT_MIN": hmin = to!uint(p[1]); break;
      case "HEIGHT_MAX": hmax = to!uint(p[1]); break;
      case "TILE_PENALTY": tilePenalty = to!float(p[1]); break;
      case "PROGRESS_RATE": progressRate = to!float(p[1]); break;
      case "INTERACTION": interaction = p[1]; break;
      case "PART_END": emitPart(); break;
      case "DROP_END": emitDrop(); break;
      case "MESH": pMesh = p[1]; break;
      case "RESOURCE": pRes = p[1]; break;
      case "SCALE_X": pSX = to!float(p[1]); break;
      case "SCALE_X_VARIANCE": pSXV = to!float(p[1]); break;
      case "SCALE_Y": pSY = (p[1] == "tileHeight" ? -1.0f : to!float(p[1])); break;
      case "SCALE_Y_VARIANCE": pSYV = to!float(p[1]); break;
      case "TAPER": pTaper = to!float(p[1]); break;
      case "OFFSET_Y": pOffY = (p[1] == "height" ? -1.0f : to!float(p[1])); break;
      case "REPEAT": pRepeat = true; break;
      case "MATERIAL": dMat = p[1]; break;
      case "DROP_MIN": dMin = to!int(p[1]); break;
      case "DROP_MAX": dMax = to!int(p[1]); break;
      case "DROP_COUNT": dMin = to!int(p[1]); dMax = dMin; break;
      case "DROP_PER_HEIGHT": dPerHeight = true; break;
      default: break;
    }
  }
  emitFeature();
  return result ~ "];\n";
}
