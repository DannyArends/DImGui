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
immutable FeatureT[] features = parseFeatures(import("data/raws/features.txt"));

/** CTFE: generates heightToResource function */
string generateHeightToResource(string raw) pure {
  auto tokens = parseTokens(raw);
  string result = "@nogc pure ResourceType heightToResource(float h, float t) nothrow {\n";
  string hi = "";
  string[] results;
  foreach(token; tokens) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    if(p[0] == "HEIGHT_RULE" && p.length == 3) {
      if(hi != "" && results.length > 0) {
        result ~= format("  if(h < %sf) { ResourceType[%s] v = [%s]; return v[cast(uint)(t * %s) %% %s]; }\n",
          hi, results.length, results.map!(r => "ResourceType." ~ r).join(", "), results.length, results.length);
      }
      hi = p[2]; results = [];
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

/** CTFE: parse raws into immutable FeatureT[] (built directly — no string codegen). */
FeatureT[] parseFeatures(string raw) pure {
  FeatureT[] features;
  FeatureT ft; FeaturePartT part; FeatureDropT drop;
  bool inFeature;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "FEATURE":          if(inFeature){features ~= ft;}
                               ft = FeatureT.init; ft.name = p[1];
                               part = FeaturePartT.init; drop = FeatureDropT.init; inFeature = true; break;
      case "SPAWN_ON":         ft.spawnOn ~= p[1]; break;
      case "NOISE_THRESHOLD":  ft.noiseThreshold = to!float(p[1]); break;
      case "HASH_SEED1":       ft.hashSeed1 = to!uint(p[1]); break;
      case "HASH_SEED2":       ft.hashSeed2 = to!uint(p[1]); break;
      case "HASH_MOD":         ft.hashMod = to!uint(p[1]); break;
      case "HASH_REM":         ft.hashRem = to!uint(p[1]); break;
      case "HEIGHT_MIN":       ft.heightMin = to!uint(p[1]); break;
      case "HEIGHT_MAX":       ft.heightMax = to!uint(p[1]); break;
      case "TILE_PENALTY":     ft.tilePenalty = to!float(p[1]); break;
      case "PROGRESS_RATE":    ft.progressRate = to!float(p[1]); break;
      case "INTERACTION":      ft.interaction = p[1]; break;
      case "SOUND":            ft.sound = p[1]; break;
      // Lsystem
      case "LSYSTEM_ANGLE":    ft.lsystemAngle = to!float(p[1]); break;
      case "AXIOM":            ft.axiom = p[1]; break;
      case "BRUSH":            if(p.length >= 7){
                                 ft.brushes ~= LSystemBrushT(p[1][0], p[2], p[3], to!float(p[4]), to!float(p[5]), to!bool(p[6]));
                               } break;
      case "RULE":             if(p.length >= 4){ ft.rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
      // Current part
      case "MESH":             part.mesh = p[1]; break;
      case "RESOURCE":         part.resourceType = p[1]; break;
      case "SCALE_X":          part.scaleX = to!float(p[1]); break;
      case "SCALE_X_VARIANCE": part.scaleXVariance = to!float(p[1]); break;
      case "SCALE_Y":          part.scaleY = (p[1] == "tileHeight" ? -1.0f : to!float(p[1])); break;
      case "SCALE_Y_VARIANCE": part.scaleYVariance = to!float(p[1]); break;
      case "TAPER":            part.taper = to!float(p[1]); break;
      case "OFFSET_Y":         part.offsetY = (p[1] == "height" ? -1.0f : to!float(p[1])); break;
      case "REPEAT":           part.repeat = true; break;
      case "PART_END":         if(part.mesh != "") ft.parts ~= part; part = FeaturePartT.init; break;
      // Current drop
      case "MATERIAL":         drop.material = p[1]; break;
      case "DROP_MIN":         drop.countMin = to!int(p[1]); break;
      case "DROP_MAX":         drop.countMax = to!int(p[1]); break;
      case "DROP_COUNT":       drop.countMin = to!int(p[1]); drop.countMax = drop.countMin; break;
      case "DROP_PER_HEIGHT":  drop.perHeight = true; break;
      case "DROP_END":         if(drop.material != "") ft.drops ~= drop; drop = FeatureDropT.init; break;
      default: break;          // LSYSTEM_BEGIN / LSYSTEM_END are markers, ignored
    }
  }
  if(inFeature) features ~= ft;
  return features;
}
