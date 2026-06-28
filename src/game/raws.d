/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import ctfe : parseTokens, splitColon;

/** NOTE: changes to .txt files require: dub build --force
 * import() is resolved at compile-time; dub does not track these as dependencies */
mixin(generateResourceEnum(import("data/raws/materials.txt")));

immutable HeightBand[] heightBands = parseHeightBands(import("data/raws/terrain.txt"));
immutable FeatureT[] features = parseFeatures(import("data/raws/features.txt"));
immutable ResourceT[] resourceTable = parseResources(import("data/raws/materials.txt"));

/** One terrain height band: an upper threshold and the resources eligible at that height. */
struct HeightBand { float threshold; ResourceType[] results; }

/** CTFE: parse terrain raws into height bands (resources resolved to enum at compile time). */
HeightBand[] parseHeightBands(string raw) pure {
  HeightBand[] bands;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    if(p[0] == "HEIGHT_RULE" && p.length == 3) {
      bands ~= HeightBand(to!float(p[2]), []);
    }else if(p[0] == "RESULT" && p.length == 2 && bands.length){ bands[$-1].results ~= p[1].to!ResourceType; }
  }
  return bands;
}

/** Surface resource for a normalised height h; t in [0,1) picks among a band's variants.
    Bands are tested in order; the last band is the unconditional fallback (its threshold is unused). */
@nogc pure ResourceType heightToResource(float h, float t) nothrow {
  foreach(ref b; heightBands[0 .. $-1]){
    if(h < b.threshold){ return(b.results[cast(uint)(t * b.results.length) % b.results.length]); }
  }
  return(heightBands[$-1].results[0]);
}

/** CTFE: generate the ResourceType enum — member names only; per-material data lives in resourceTable. */
string generateResourceEnum(string raw) pure {
  string result = "enum ResourceType : ubyte {\n";
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length >= 2 && p[0] == "MATERIAL") result ~= "  " ~ p[1] ~ ",\n";
  }
  return result ~ "}\n";
}

/** CTFE: resolve a Colors member by name, defaults to white. */
Colors toColor(string name) pure {
  static foreach(m; __traits(allMembers, Colors)) if(name == m) return __traits(getMember, Colors, m);
  return Colors.white;
}

/** CTFE: parse materials into the per-ResourceType data table (parallel to the enum's member order). */
ResourceT[] parseResources(string raw) pure {
  ResourceT[] table; ResourceT cur; bool inMat;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "MATERIAL":    if(inMat) table ~= cur; cur = ResourceT.init; cur.name = p[1]; inMat = true; break;
      case "TEXTURE":     cur.name = p[1]; break;
      case "TRAVERSABLE": cur.traversable = true; break;
      case "BUILDABLE":   cur.buildable = true; break;
      case "MESH":        cur.meshName = p[1]; break;
      case "SCALE":       cur.dropScale = to!float(p[1]); break;
      case "COST":        cur.cost = to!float(p[1]); break;
      case "MAX_STACK":   cur.maxStack = cast(ubyte)to!int(p[1]); break;
      case "COLOR":       cur.color = toColor(p[1]); break;
      default: break;
    }
  }
  if(inMat){ table ~= cur; }
  return(table);
}

/** Per-material data, indexed by ResourceType (enum's ubyte value indexes the table). */
@nogc pure ResourceT resourceData(ResourceType rt) nothrow { return resourceTable[rt]; }

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
      case "LSYSTEM_ANGLE":    ft.lsystemYaw = ft.lsystemPitch = ft.lsystemRoll = to!float(p[1]); break;
      case "LSYSTEM_YAW":      ft.lsystemYaw   = to!float(p[1]); break;
      case "LSYSTEM_PITCH":    ft.lsystemPitch = to!float(p[1]); break;
      case "LSYSTEM_ROLL":     ft.lsystemRoll  = to!float(p[1]); break;
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
  if(inFeature){ features ~= ft; }
  return(features);
}
