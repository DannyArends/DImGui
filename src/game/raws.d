/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import color : toColor;
import ctfe : parseRawsGeneric, parseTokens, splitColon;
import lsystem : Effect, Rule, Symbol, GEN_END;
import turtlegfx : AnimClip;
import rawstructs;

/** NOTE: changes to .txt files require: dub build --force
 * import() is resolved at compile-time; dub does not track these as dependencies */

/** Pick a result from a band by the [0,1) selector `t` (uniform bucket over results). */
@nogc pure nothrow ResourceType rSelect(ref const HeightBand b, float t) { return b.results[cast(uint)(t * b.results.length) % b.results.length]; }

/** CTFE: parse terrain raws into height bands (resources resolved to enum at compile time). */
HeightBand[] parseHeightBands(string raw) pure {
  HeightBand[] bands;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    if(p[0] == "HEIGHT_RULE" && p.length == 3) {
      bands ~= HeightBand(to!float(p[2]), []);
    }else if(p[0] == "RESULT" && p.length == 2 && bands.length) { bands[$-1].results ~= p[1].to!ResourceType; }
  }
  return(bands);
}

/** Surface resource for a normalised height h; t in [0,1) picks among a band's variants.
    Bands are tested in order; the last band is the unconditional fallback (its threshold is unused). */
@nogc pure ResourceType heightToResource(float h, float t) nothrow {
  foreach(ref b; heightBands) { if(h < b.threshold) { return(b.rSelect(t)); } }
  return(heightBands[$-1].rSelect(t));
}

ResourceT[] parseResources(string tilesRaw) pure { return parseRawsGeneric!(ResourceT, "TILE", (ref cur, p) {
  switch(p[0]) {
    case "SUBSTANCE":   cur.substance = p[1].to!Substance; break;
    case "MESH":        if(p.length > 1) cur.meshName = p[1];
                        if(p.length > 2) cur.color    = toColor(p[2]);
                        if(p.length > 3) cur.tex3D    = p[3];
                        if(p.length > 4) cur.tex2D    = p[4]; break;
    case "TRAVERSABLE": cur.traverse = p.length > 1 ? p[1].to!float : 1.0f; break;
    case "BUILDABLE":   cur.build = true; break;
    case "STACK":       cur.maxStack = p[1].to!int; break;
    default: break;
  }
})(tilesRaw); }

/** CTFE: build the variant table (parallel to the ResourceType enum) from tiles + feature brushes.
 *  A tile IS a variant (its name is the enum member); a feature brush yields a substance@feature variant. */
ResourceT[] parseVariants(string tilesRaw, string featuresRaw) pure {
  ResourceT[] table = tilesRaw.parseResources();

  // Feature variants: each distinct brush substance in a feature -> a <Feature><Substance> variant,
  // carrying that brush's mesh, texture, edibility and source. First brush of a substance wins.
  string feat; string[] seen;
  foreach(token; parseTokens(featuresRaw)) {
    auto p = splitColon(token);
    if(p.length >= 2 && p[0] == "FEATURE") { feat = p[1]; continue; }
    if(p.length >= 5 && p[0] == "BRUSH") {
      string member = feat ~ p[3];
      bool dup = false; foreach(x; seen) if(x == member) dup = true;
      if(dup) continue;
      seen ~= member;
      table ~= ResourceT(name: member, meshName: p[2], tex3D: p[4], tex2D: p[4],
                         scale: p.length > 10 ? p[10].to!float : 1.0f,
                         offsetY: p.length > 11 ? p[11].to!float : 0.0f,
                         substance: p[3].to!Substance,
                         source: feat.to!Source,
                         food: p.length > 8 ? p[8].to!float : 0.0f);
    }
  }
  return table;
}

/** CTFE: parse items.txt into the per-template table (index 0 == ItemTemplate.None, then parallel to the enum). */
ItemTemplateT[] parseItemTemplates(string raw) pure { return parseRawsGeneric!(ItemTemplateT, "ITEM", (ref cur, p) {
  switch(p[0]) {
    case "MESH":     if(p.length > 1) cur.mesh = p[1];
                     if(p.length > 2) cur.tex3D = p[2];
                     if(p.length > 3) cur.tex = p[3];
                     if(p.length > 4) cur.texFilled = p[4]; break;
    case "ACCEPTS":  cur.accepts ~= p[1].to!Substance; break;
    case "HOLDS":    cur.holds   ~= p[1].to!Substance; break;
    case "CAPACITY": cur.capacity = to!uint(p[1]); break;
    case "SCALE":    cur.scale = to!float(p[1]); break;
    case "OFFSET_Y": cur.offsetY = to!float(p[1]); break;
    case "STACK":    cur.maxStack = to!int(p[1]); break;
    case "FOOD":     cur.food = to!float(p[1]); break;
    default: break;
  }
})(raw, true); }

/** CTFE: parse raws into immutable FeatureT[] (built directly — no string codegen). */
FeatureT[] parseFeatures(string raw) pure { return parseRawsGeneric!(FeatureT, "FEATURE", (ref ft, p) {
  switch(p[0]) {
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
    case "BRUSH": if(p.length >= 8){
      ft.brushes ~= LSystemBrushT(p[1][0], p[2], p[3].to!Substance, p[4],
        to!float(p[5]), to!float(p[6]), to!bool(p[7]),
        p.length > 8 ? to!float(p[8]) : 0.0f,
        p.length > 9 ? to!bool(p[9]) : true,
        p.length > 10 ? to!float(p[10]) : 1.0f);
    } break;
    case "RULE":             if(p.length >= 4){ ft.rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
    // Current part
    default: break;          // LSYSTEM_BEGIN / LSYSTEM_END are markers, ignored
  }
})(raw); }

/** CTFE: parse [ENTITY] blocks into per-species EntityT. Entity brushes carry no substance (0). */
EntityT[] parseEntities(string raw) pure { return parseRawsGeneric!(EntityT, "ENTITY", (ref e, p) {
  switch(p[0]) {
    case "MOVE_SPEED":       e.moveSpeed = to!float(p[1]); break;
    case "SPAWN_ON":         e.spawnOn ~= p[1].to!ResourceType; break;
    case "NOISE_THRESHOLD":  e.noiseThreshold = to!float(p[1]); break;
    case "HASH_SEED1":       e.hashSeed1 = to!uint(p[1]); break;
    case "HASH_SEED2":       e.hashSeed2 = to!uint(p[1]); break;
    case "HASH_MOD":         e.hashMod = to!uint(p[1]); break;
    case "HASH_REM":         e.hashRem = to!uint(p[1]); break;
    case "HUNGER_DECAY":     e.hungerDecay = to!float(p[1]); break;
    case "THIRST_DECAY":     e.thirstDecay = to!float(p[1]); break;
    case "DIET":             e.diet = p[1]; break;
    case "SCALE":            e.scale = to!float(p[1]); break;
    case "SCALE_VARIANCE":   e.scaleVariance = to!float(p[1]); break;
    case "OFFSET_Y":         e.offsetY = to!float(p[1]); break;
    case "FACING":           e.facing = to!float(p[1]); break;
    case "LSYSTEM_ANGLE":    e.lsystemYaw = e.lsystemPitch = e.lsystemRoll = to!float(p[1]); break;
    case "LSYSTEM_GAP":      e.lsystemGap = to!float(p[1]); break;
    case "LSYSTEM_YAW":      e.lsystemYaw   = to!float(p[1]); break;
    case "LSYSTEM_PITCH":    e.lsystemPitch = to!float(p[1]); break;
    case "LSYSTEM_ROLL":     e.lsystemRoll  = to!float(p[1]); break;
    case "AXIOM":            e.axiom = p[1]; break;
    case "LSYSTEM_ITER":     e.lsystemIter = to!uint(p[1]); break;
    case "BRUSH": if(p.length >= 6){
      immutable bool tnt = p.length > 6 && p[6] == "tint";
      immutable float[4] col = (p.length > 6 && !tnt) ? cast(float[4])toColor(p[6]) : [1.0f, 1.0f, 1.0f, 1.0f];
      immutable float[3] off = [p.length > 7 ? to!float(p[7]) : 0.0f,
                                p.length > 8 ? to!float(p[8]) : 0.0f,
                                p.length > 9 ? to!float(p[9]) : 0.0f];
      immutable float dep = p.length > 10 ? to!float(p[10]) : -1.0f;   // -1 -> square section
      e.brushes ~= LSystemBrushT(p[1][0], p[2], Substance.init, "", to!float(p[3]), to!float(p[4]), to!bool(p[5]),
                                 0.0f, true, 1.0f, off, col, tnt, dep);
    } break;
    case "RULE": if(p.length >= 4){
      int gmin = 0, gmax = int.max;
      if(p.length > 4 && p[4].length){ gmin = (p[4] == "@") ? GEN_END : to!int(p[4]); }
      if(p.length > 5 && p[5].length){ gmax = (p[5] == "@") ? GEN_END : to!int(p[5]); }
      e.rules ~= Rule(p[1][0], p[2], to!uint(p[3]), gmin, gmax);
    } break;
    case "CLIP": if(p.length >= 2){       // [CLIP:name:axiom:whenMoving:fps]
      e.clips ~= AnimClip(p[1], p.length > 2 ? p[2] : "", [], (Symbol[char]).init,
                          p.length > 3 && p[3] == "moving", p.length > 4 ? to!float(p[4]) : 8.0f,
                          p.length > 5 ? to!float(p[5]) : 25.0f);
    } break;
    case "CRULE":            if(p.length >= 4 && e.clips.length){ e.clips[$-1].rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
    case "POSE": if(p.length >= 3 && e.clips.length){    // [POSE:sym:target:side:axis]  axis = X|Y|Z (world swing)
      float[3] ax = [0.0f, 0.0f, 0.0f];
      if(p.length > 4) { if(p[4] == "X") ax = [1,0,0]; else if(p[4] == "Y") ax = [0,1,0]; else if(p[4] == "Z") ax = [0,0,1]; }
      Symbol ps = { effect: Effect.pose, target: p[2][0], bySide: p.length > 3 && p[3] == "side", axis: ax };
      e.clips[$-1].poses[p[1][0]] = ps;
    } break;
    default: break;
  }
})(raw); }

Reaction[] parseReactions(string raw) pure { return parseRawsGeneric!(Reaction, "REACTION", (ref r, p) {
  switch(p[0]) {
    case "VERB": r.verb  = p[1]; break;
    case "SKILL": r.skill = p[1]; break;
    case "WORKSHOP": r.workshop = p[1].to!WorkshopUse; break;
    case "PROGRESS_RATE": r.progressRate = to!float(p[1]); break;
    case "INPUT": if(p.length >= 3) r.inputs  ~= Ingredient(p[1].to!Substance, ItemTemplate.init, p[2].to!uint); break;
    case "INPUT_ITEM": if(p.length >= 3) r.inputs ~= Ingredient(Substance.init, p[1].to!ItemTemplate, p[2].to!uint); break;
    case "OUTPUT": if(p.length >= 3) r.outputs ~= Product(ItemTemplate.init, p[1].to!ResourceType, Substance.init, 1.0f, p[2].to!uint); break;
    case "OUTPUT_ITEM": if(p.length >= 4) r.outputs ~= Product(p[1].to!ItemTemplate, ResourceType.init, p[2].to!Substance, 1.0f, p[3].to!uint); break;
    default: break;
  }
})(raw); }

/** CTFE: turtle control chars that never map to a brush or pose. */
private bool isControl(char c) pure { return "fX()+-&^<> \t\r\n".canFind(c); }

/** CTFE: symbols an entity/clip grammar can produce (axiom + every rule production). */
private bool[char] produced(string axiom, const Rule[] rules) pure {
  bool[char] s; foreach(c; axiom) s[c] = true;
  foreach(ref r; rules) foreach(c; r.production) s[c] = true;
  return s;
}

/** CTFE: first symbol-consistency error across all entities ("" == valid). */
string validateEntities(const EntityT[] es) pure {
  foreach(ref e; es) {
    bool[char] brush; foreach(ref b; e.brushes) brush[b.symbol] = true;
    foreach(c, _; produced(e.axiom, e.rules))
      if(!isControl(c) && c !in brush && e.rules.all!(r => r.predecessor != c))
        return e.name ~ ": body symbol '" ~ c ~ "' has no [BRUSH] and no [RULE]";
    foreach(ref cl; e.clips) {
      auto emitted = produced(cl.axiom, cl.rules);
      foreach(sym, ref pb; cl.poses) {
        if(sym !in emitted) return e.name ~ "/" ~ cl.name ~ ": [POSE] symbol '" ~ sym ~ "' never produced by the clip";
        if(pb.target !in brush) return e.name ~ "/" ~ cl.name ~ ": [POSE] target '" ~ pb.target ~ "' has no [BRUSH]";
      }
    }
  }
  return "";
}

/** CTFE: per-feature spawn membership mask indexed by ResourceType, parallel to `features`. */
private SpawnMask spawnMask(const FeatureT ft) pure {
  SpawnMask m; foreach(s; ft.spawnOn) { auto rt = (s == "None" ? ResourceType.None : s.to!ResourceType); m[rt] = true; } return m;
}

immutable SpawnMask[] featureSpawnMask = () { SpawnMask[] a; foreach(ref ft; featureTable) a ~= spawnMask(ft); return a; }();

/** Precomputes an O(1) lookup table mapping ResourceType to matching animal indices. */
enum spawnLookup= () {
  SpawnGroup!(entityTable.length)[RESOURCE_COUNT] lookup;
  foreach(size_t aType, ref at; entityTable) { foreach(st; at.spawnOn) { lookup[st].animalIndices[lookup[st].count++] = aType; } }
  return lookup;
}();

// Tables
immutable HeightBand[] heightBands = parseHeightBands(import("data/raws/terrain.txt"));
immutable FeatureT[] featureTable = parseFeatures(import("data/raws/features.txt"));
immutable ResourceT[] resourceTable = parseVariants(import("data/raws/tiles.txt"), import("data/raws/features.txt"));
immutable Reaction[] reactionTable = parseReactions(import("data/raws/reactions.txt"));
immutable ItemTemplateT[] itemTemplateTable = parseItemTemplates(import("data/raws/items.txt"));
immutable EntityT[] entityTable = parseEntities(import("data/raws/entity.txt"));

static assert(resourceTable.length == RESOURCE_COUNT, "resourceTable out of sync with ResourceType enum");
static assert(itemTemplateTable.length == ItemTemplate.max + 1, "itemTemplateTable out of sync with ItemTemplate enum");
static assert(validateEntities(entityTable).length == 0, validateEntities(entityTable));