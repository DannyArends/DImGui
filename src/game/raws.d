/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import color : toColor;
import ctfe : parseTokens, splitColon, toEnum;
import lsystem : LSystemBrushT, Rule;    // brush/rule types used when parsing
import rawstructs;

/** NOTE: changes to .txt files require: dub build --force
 * import() is resolved at compile-time; dub does not track these as dependencies */

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
    if(h < b.threshold){ return(cast(ResourceType)b.results[cast(uint)(t * b.results.length) % b.results.length]); }
  }
  return(cast(ResourceType)heightBands[$-1].results[0]);
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
      v.offsetY   = p.length > 11 ? to!float(p[11]) : 0.0f;
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
  FeatureT[] list;
  FeatureT ft; bool inFeature;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "FEATURE":          if(inFeature){list ~= ft;}
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
      case "BRUSH": if(p.length >= 8){
        immutable ubyte sub = p[3].toEnum!Substance;   // __traits-based, resolved before the ctor
        ft.brushes ~= LSystemBrushT(p[1][0], p[2], sub, p[4],
          to!float(p[5]), to!float(p[6]), to!bool(p[7]),
          p.length > 8 ? to!float(p[8]) : 0.0f,
          p.length > 9 ? to!bool(p[9]) : true,
          p.length > 10 ? to!float(p[10]) : 1.0f);
      } break;
      case "RULE":             if(p.length >= 4){ ft.rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
      // Current part
      default: break;          // LSYSTEM_BEGIN / LSYSTEM_END are markers, ignored
    }
  }
  if(inFeature){ list ~= ft; }
  return(list);
}

/** CTFE: parse [ENTITY] blocks into per-species EntityT. Entity brushes carry no substance (0). */
EntityT[] parseEntities(string raw) pure {
  EntityT[] entities; EntityT e; bool inEntity;
  foreach(token; parseTokens(raw)) {
    auto p = splitColon(token);
    if(p.length == 0) continue;
    switch(p[0]) {
      case "ENTITY":           if(inEntity){ entities ~= e; } e = EntityT.init; e.name = p[1]; inEntity = true; break;
      case "MOVE_SPEED":       e.moveSpeed = to!float(p[1]); break;
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
      case "BRUSH": if(p.length >= 6){
        immutable float[4] col = p.length > 6 ? cast(float[4])toColor(p[6]) : [1.0f, 1.0f, 1.0f, 1.0f];
        immutable float[3] off = [p.length > 7 ? to!float(p[7]) : 0.0f,
                                  p.length > 8 ? to!float(p[8]) : 0.0f,
                                  p.length > 9 ? to!float(p[9]) : 0.0f];
        e.brushes ~= LSystemBrushT(p[1][0], p[2], 0, "", to!float(p[3]), to!float(p[4]), to!bool(p[5]),
                                   0.0f, true, 1.0f, off, col);
      } break;
      case "RULE":             if(p.length >= 4){ e.rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
      default: break;
    }
  }
  if(inEntity){ entities ~= e; }
  return(entities);
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

/** CTFE: per-feature spawn membership mask indexed by ResourceType, parallel to `features`. */
private SpawnMask spawnMask(const FeatureT ft) pure {
  SpawnMask m;
  foreach(s; ft.spawnOn) { auto rt = (s == "None" ? ResourceType.None : s.to!ResourceType); m[rt] = true; }
  return m;
}
immutable SpawnMask[] featureSpawnMask = () {
  SpawnMask[] a; foreach(ref ft; features) a ~= spawnMask(ft); return a; 
}();

// Tables (below all enum mixins: their CTFE pulls resources->game->raws, so every enum must exist first).
immutable HeightBand[] heightBands = parseHeightBands(import("data/raws/terrain.txt"));
immutable FeatureT[] features = parseFeatures(import("data/raws/features.txt"));
immutable ResourceT[] resourceTable = parseVariants(import("data/raws/tiles.txt"), import("data/raws/features.txt"));
immutable Reaction[] reactionTable = parseReactions(import("data/raws/reactions.txt"));
immutable ItemTemplateT[] itemTemplateTable = parseItemTemplates(import("data/raws/items.txt"));
immutable AnimalT[] animalTable = parseAnimals(import("data/raws/animals.txt"));
immutable EntityT[] entityTable = parseEntities(import("data/raws/entity.txt"));

static assert(resourceTable.length == RESOURCE_COUNT, "resourceTable out of sync with ResourceType enum");
static assert(itemTemplateTable.length == ItemTemplate.max + 1, "itemTemplateTable out of sync with ItemTemplate enum");
