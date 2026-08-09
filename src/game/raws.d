/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import ctfe : parseTokens, splitColon;

/** NOTE: changes to .txt files require: dub build --force
 * import() is resolved at compile-time; dub does not track these as dependencies */
// Substance = the abstract match key (Stone, Wood, ...). Replaces the old [CLASS:x] name-hack.
mixin(enumFromTag(import("data/raws/substance.txt"), "SUBSTANCE", "Substance", "None"));
mixin(sourceEnum(import("data/raws/tiles.txt"), import("data/raws/features.txt")));

// A ResourceType is a variant = substance @ source. Sources are tiles (terrain) and feature brushes.
// The variant table is built first; the ResourceType enum is generated from its member names (preserved).
mixin(variantEnum(import("data/raws/tiles.txt"), import("data/raws/features.txt")));
enum size_t RESOURCE_COUNT = ResourceType.max + 1;   /// Number of ResourceType members (variants)

mixin(enumFromTag(import("data/raws/items.txt"), "ITEM", "ItemTemplate", "None"));

// Tables (below all enum mixins: their CTFE pulls resources->game->raws, so every enum must exist first).
immutable HeightBand[] heightBands = parseHeightBands(import("data/raws/terrain.txt"));
immutable FeatureT[] features = parseFeatures(import("data/raws/features.txt"));
immutable ResourceT[] resourceTable = parseVariants(import("data/raws/tiles.txt"), import("data/raws/features.txt"));
immutable Reaction[] reactionTable = parseReactions(import("data/raws/reactions.txt"));
immutable ItemTemplateT[] itemTemplateTable = parseItemTemplates(import("data/raws/items.txt"));
immutable AnimalT[] animalTable = parseAnimals(import("data/raws/animals.txt"));

static assert(resourceTable.length == RESOURCE_COUNT, "resourceTable out of sync with ResourceType enum");
static assert(itemTemplateTable.length == ItemTemplate.max + 1, "itemTemplateTable out of sync with ItemTemplate enum");

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

/** CTFE: 'enum ResourceType : ubyte { <member per [TILE:x], then <Feature><Substance> per brush> }'.
 *  Parses the raw strings directly (like enumFromTag) so it is a compile-time mixin argument;
 *  parseVariants walks the same order so resourceTable stays parallel to the enum. */
string variantEnum(string tilesRaw, string featuresRaw) pure {
  string result = "enum ResourceType : ubyte {\n";
  foreach(token; parseTokens(tilesRaw)) {
    auto p = splitColon(token);
    if(p.length >= 2 && p[0] == "TILE") result ~= "  " ~ p[1] ~ ",\n";
  }
  string feat; string[] seen;
  foreach(token; parseTokens(featuresRaw)) {
    auto p = splitColon(token);
    if(p.length >= 2 && p[0] == "FEATURE") { feat = p[1]; continue; }
    if(p.length >= 4 && p[0] == "BRUSH") {
      string member = feat ~ p[3];                      // <Feature><Substance>
      bool dup = false; foreach(x; seen) if(x == member) dup = true;
      if(!dup){ seen ~= member; result ~= "  " ~ member ~ ",\n"; }
    }
  }
  return result ~ "}\n";
}

/** CTFE: 'enum Source : ubyte { None, <tile names>, <feature names> }' — a variant's origin axis. */
string sourceEnum(string tilesRaw, string featuresRaw) pure {
  string result = "enum Source : ubyte {\n  None,\n";
  foreach(token; parseTokens(tilesRaw)) { auto p = splitColon(token); if(p.length >= 2 && p[0] == "TILE" && p[1] != "None") result ~= "  " ~ p[1] ~ ",\n"; }
  foreach(token; parseTokens(featuresRaw)) { auto p = splitColon(token); if(p.length >= 2 && p[0] == "FEATURE") result ~= "  " ~ p[1] ~ ",\n"; }
  return result ~ "}\n";
}

/** CTFE: resolve a Colors member by name, defaults to white. */
Colors toColor(string name) pure {
  static foreach(m; __traits(allMembers, Colors)) if(name == m) return __traits(getMember, Colors, m);
  return Colors.white;
}

/** CTFE: build the variant table (parallel to the ResourceType enum) from tiles + feature brushes.
 *  A tile IS a variant (its name is the enum member); a feature brush yields a substance@feature variant. */
ResourceT[] parseVariants(string tilesRaw, string featuresRaw) pure {
  ResourceT[] table; ResourceT cur; bool inTile;
  foreach(token; parseTokens(tilesRaw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "TILE":        if(inTile) table ~= cur; cur = ResourceT.init; cur.name = p[1]; cur.source = cast(ubyte)p[1].to!Source; inTile = true; break;
      case "SUBSTANCE":   cur.substance = cast(ubyte)p[1].to!Substance; break;
      case "MESH":        // MESH:mesh:color:tex3D:tex2D
        if(p.length > 1) cur.meshName = p[1];
        if(p.length > 2) cur.color    = toColor(p[2]);
        if(p.length > 3) cur.tex3D    = p[3];
        if(p.length > 4) cur.tex2D    = p[4];
        break;
      case "TRAVERSABLE": cur.traverse = p.length > 1 ? to!float(p[1]) : 1.0f; break;
      case "BUILDABLE":   cur.build = true; break;
      case "STACK":       cur.maxStack = to!int(p[1]); break;
      default: break;
    }
  }
  if(inTile) table ~= cur;
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
      ResourceT v;
      v.name      = member;
      v.substance = cast(ubyte)p[3].to!Substance;
      v.source    = cast(ubyte)feat.to!Source;
      v.meshName  = p[2];
      v.scale     = p.length > 10 ? to!float(p[10]) : 1.0f;
      v.tex3D = p[4]; v.tex2D = p[4];
      if(p.length > 8) v.food = to!float(p[8]);
      table ~= v;
    }
  }
  return table;
}

/** Per-material data, indexed by ResourceType (enum's ubyte value indexes the table). */
@nogc pure const(ResourceT) resourceData(ResourceType rt) nothrow { return resourceTable[rt]; }

/** Per-template data, indexed by ItemTemplate (enum's ubyte value indexes the table). */
@nogc pure const(ItemTemplateT) templateData(ItemTemplate t) nothrow { return itemTemplateTable[t]; }

/** CTFE: parse items.txt into the per-template table (index 0 == ItemTemplate.None, then parallel to the enum). */
ItemTemplateT[] parseItemTemplates(string raw) pure {
  ItemTemplateT[] table; ItemTemplateT cur; bool inItem;
  table ~= ItemTemplateT("None");                          // index 0 == ItemTemplate.None
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "ITEM":     if(inItem) table ~= cur; cur = ItemTemplateT.init; cur.name = p[1]; inItem = true; break;
      case "MESH":     if(p.length > 1) cur.mesh = p[1];
                       if(p.length > 2) cur.tex3D = p[2];
                       if(p.length > 3) cur.tex = p[3];
                       if(p.length > 4) cur.texFilled = p[4]; break;
      case "ACCEPTS":  cur.accepts ~= cast(ubyte)p[1].to!Substance; break;
      case "HOLDS":    cur.holds   ~= cast(ubyte)p[1].to!Substance; break;
      case "CAPACITY": cur.capacity = to!uint(p[1]); break;
      case "SCALE":    cur.scale = to!float(p[1]); break;
      case "OFFSET_Y": cur.offsetY = to!float(p[1]); break;
      case "STACK":    cur.maxStack = to!int(p[1]); break;
      case "FOOD":     cur.food = to!float(p[1]); break;
      default: break;
    }
  }
  if(inItem) table ~= cur;
  return table;
}

/** CTFE: parse animal raws into species definitions. */
AnimalT[] parseAnimals(string raw) pure {
  AnimalT[] animals;
  AnimalT a; bool inAnimal;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "ANIMAL":           if(inAnimal){ animals ~= a; } a = AnimalT.init; a.name = p[1]; inAnimal = true; break;
      case "MESH":             a.mesh = p[1]; break;
      case "SPAWN_ON":         a.spawnOn ~= p[1].to!ResourceType; break;
      case "NOISE_THRESHOLD":  a.noiseThreshold = to!float(p[1]); break;
      case "HASH_SEED1":       a.hashSeed1 = to!uint(p[1]); break;
      case "HASH_SEED2":       a.hashSeed2 = to!uint(p[1]); break;
      case "HASH_MOD":         a.hashMod = to!uint(p[1]); break;
      case "HASH_REM":         a.hashRem = to!uint(p[1]); break;
      case "MOVE_SPEED":       a.moveSpeed = to!float(p[1]); break;
      case "HUNGER_DECAY":     a.hungerDecay = to!float(p[1]); break;
      case "THIRST_DECAY":     a.thirstDecay = to!float(p[1]); break;
      case "DIET":             a.diet = p[1]; break;
      case "SCALE":            a.scale = to!float(p[1]); break;
      case "SCALE_VARIANCE":   a.scaleVariance = to!float(p[1]); break;
      case "OFFSET_Y":         a.offsetY = to!float(p[1]); break;
      case "FACING":           a.facing = to!float(p[1]); break;
      default: break;
    }
  }
  if(inAnimal){ animals ~= a; }
  return animals;
}

/** CTFE: parse raws into immutable FeatureT[] (built directly — no string codegen). */
FeatureT[] parseFeatures(string raw) pure {
  FeatureT[] features;
  FeatureT ft;
  bool inFeature;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "FEATURE":          if(inFeature){features ~= ft;}
                               ft = FeatureT.init; ft.name = p[1];
                               inFeature = true; break;
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
      case "BRUSH":            if(p.length >= 8){
                                 ft.brushes ~= LSystemBrushT(p[1][0], p[2], cast(ubyte)p[3].to!Substance, p[4], to!float(p[5]), to!float(p[6]), to!bool(p[7]), p.length > 8 ? to!float(p[8]) : 0.0f, p.length > 9 ? to!bool(p[9]) : true, p.length > 10 ? to!float(p[10]) : 1.0f);
                               } break;
      case "RULE":             if(p.length >= 4){ ft.rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
      // Current part
      default: break;          // LSYSTEM_BEGIN / LSYSTEM_END are markers, ignored
    }
  }
  if(inFeature){ features ~= ft; }
  return(features);
}

Reaction[] parseReactions(string raw) pure {
  Reaction[] table; Reaction r; bool inReaction;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "REACTION": if(inReaction) table ~= r; r = Reaction.init; r.name = p[1]; inReaction = true; break;
      case "VERB": r.verb  = p[1]; break;
      case "SKILL": r.skill = p[1]; break;
      case "WORKSHOP": r.workshop = p[1].to!WorkshopUse; break;
      case "PROGRESS_RATE": r.progressRate = to!float(p[1]); break;
      case "INPUT": if(p.length >= 3) r.inputs  ~= Ingredient(cast(ubyte)p[1].to!Substance, 0, p[2].to!uint); break;
      case "INPUT_ITEM": if(p.length >= 3) r.inputs ~= Ingredient(0, cast(ubyte)p[1].to!ItemTemplate, p[2].to!uint); break;
      case "OUTPUT": if(p.length >= 3) r.outputs ~= Product(0, cast(ubyte)p[1].to!ResourceType, 0, 1.0f, p[2].to!uint); break;
      case "OUTPUT_ITEM": if(p.length >= 4) r.outputs ~= Product(cast(ubyte)p[1].to!ItemTemplate, 0, cast(ubyte)p[2].to!Substance, 1.0f, p[3].to!uint); break;
      default: break;
    }
  }
  if(inReaction) table ~= r;
  return table;
}

