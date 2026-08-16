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

/** Parse a grammar token (AXIOM/RULE/LSYSTEM_*) shared by every raw template. Returns true if handled. */
bool parseGrammarToken(ref string axiom, ref Rule[] rules,
                       ref float yaw, ref float pitch, ref float roll, const string[] p) pure {
  switch(p[0]) {
    case "AXIOM":         axiom = p[1]; return true;
    case "LSYSTEM_ANGLE": yaw = pitch = roll = to!float(p[1]); return true;
    case "LSYSTEM_YAW":   yaw   = to!float(p[1]); return true;
    case "LSYSTEM_PITCH": pitch = to!float(p[1]); return true;
    case "LSYSTEM_ROLL":  roll  = to!float(p[1]); return true;
    case "RULE": if(p.length >= 4){
      int gmin = 0, gmax = int.max;
      if(p.length > 4 && p[4].length){ gmin = (p[4] == "@") ? GEN_END : to!int(p[4]); }
      if(p.length > 5 && p[5].length){ gmax = (p[5] == "@") ? GEN_END : to!int(p[5]); }
      rules ~= Rule(p[1][0], p[2], to!uint(p[3]), gmin, gmax);
    } return true;
    default: return false;
  }
}
/** One raw handler for every template: grammar tokens (via parseGrammarToken) + all domain tokens. A
    features file never emits MOVE_SPEED, a pawn file never emits HEIGHT_MIN — one parser, no drift. */
void rawHandler(ref EntityT x, const string[] p) pure {
  if(parseGrammarToken(x.axiom, x.rules, x.lsystemYaw, x.lsystemPitch, x.lsystemRoll, p)) return;
  switch(p[0]) {
    // shared spawn gate
    case "SPAWN_ON":         x.spawnOn ~= p[1].to!ResourceType; break;
    case "NOISE_THRESHOLD":  x.noiseThreshold = to!float(p[1]); break;
    case "HASH_SEED1":       x.hashSeed1 = to!uint(p[1]); break;
    case "HASH_SEED2":       x.hashSeed2 = to!uint(p[1]); break;
    case "HASH_MOD":         x.hashMod = to!uint(p[1]); break;
    case "HASH_REM":         x.hashRem = to!uint(p[1]); break;
    // vegetation domain
    case "HEIGHT_MIN":       x.heightMin = to!uint(p[1]); break;
    case "HEIGHT_MAX":       x.heightMax = to!uint(p[1]); break;
    case "TILE_PENALTY":     x.tilePenalty = to!float(p[1]); break;
    case "PROGRESS_RATE":    x.progressRate = to!float(p[1]); break;
    case "INTERACTION":      x.interaction = p[1]; break;
    case "SOUND":            x.sound = p[1]; break;
    // pawn domain
    case "MOVE_SPEED":       x.moveSpeed = to!float(p[1]); break;
    case "HUNGER_DECAY":     x.hungerDecay = to!float(p[1]); break;
    case "THIRST_DECAY":     x.thirstDecay = to!float(p[1]); break;
    case "DIET":             x.diet = p[1]; break;
    case "SCALE":            x.scale = to!float(p[1]); break;
    case "SCALE_VARIANCE":   x.scaleVariance = to!float(p[1]); break;
    case "OFFSET_Y":         x.offsetY = to!float(p[1]); break;
    case "FACING":           x.facing = to!float(p[1]); break;
    case "LSYSTEM_GAP":      x.lsystemGap = to!float(p[1]); break;
    case "LSYSTEM_ITER":     x.lsystemIter = to!uint(p[1]); break;
    case "BRUSH": if(p.length >= 6){
      LSystemBrushT b = { symbol: p[1][0], mesh: p[2], radius: to!float(p[3]), length: to!float(p[4]), advance: to!bool(p[5]) };
      foreach(kv; p[6 .. $]) {
        immutable e = kv.indexOf('=');                 // "key=value"; bare "tint" allowed
        immutable string k = (e < 0) ? kv : kv[0 .. e];
        immutable string v = (e < 0) ? "" : kv[e + 1 .. $];
        switch(k) {
          case "substance": b.substance = v.to!Substance; break;
          case "texture":   b.texture = v; break;
          case "food":      b.food = to!float(v); break;
          case "render":    b.render = to!bool(v); break;
          case "dropScale": b.dropScale = to!float(v); break;
          case "color":     b.color = cast(float[4])toColor(v); break;
          case "tint":      b.tint = true; break;
          case "offX":      b.offset[0] = to!float(v); break;
          case "offY":      b.offset[1] = to!float(v); break;
          case "offZ":      b.offset[2] = to!float(v); break;
          case "depth":     b.depth = to!float(v); break;
          default: break;
        }
      }
      x.brushes ~= b;
    } break;
    case "CLIP": if(p.length >= 2){
      x.clips ~= AnimClip(p[1], p.length > 2 ? p[2] : "", [], (Symbol[char]).init,
                          p.length > 3 && p[3] == "moving", p.length > 4 ? to!float(p[4]) : 8.0f,
                          p.length > 5 ? to!float(p[5]) : 25.0f);
    } break;
    case "CRULE": if(p.length >= 4 && x.clips.length){ x.clips[$-1].rules ~= Rule(p[1][0], p[2], to!uint(p[3])); } break;
    case "POSE": if(p.length >= 3 && x.clips.length){
      float[3] ax = [0.0f, 0.0f, 0.0f];
      if(p.length > 4) { if(p[4] == "X") ax = [1,0,0]; else if(p[4] == "Y") ax = [0,1,0]; else if(p[4] == "Z") ax = [0,0,1]; }
      Symbol ps = { effect: Effect.pose, target: p[2][0], bySide: p.length > 3 && p[3] == "side", axis: ax };
      x.clips[$-1].poses[p[1][0]] = ps;
    } break;
    default: break;
  }
}
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
private SpawnMask spawnMask(const EntityT ft) pure {
  SpawnMask m; foreach(rt; ft.spawnOn) m[rt] = true; return m;
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
immutable ResourceT[] resourceTable = parseVariants(import("data/raws/tiles.txt"), import("data/raws/features.txt"));
immutable Reaction[] reactionTable = parseReactions(import("data/raws/reactions.txt"));
immutable ItemTemplateT[] itemTemplateTable = parseItemTemplates(import("data/raws/items.txt"));
immutable EntityT[] featureTable = parseRawsGeneric!(EntityT, "FEATURE", rawHandler)(import("data/raws/features.txt"));
immutable EntityT[] entityTable  = parseRawsGeneric!(EntityT, "ENTITY",  rawHandler)(import("data/raws/entity.txt"));

static assert(resourceTable.length == RESOURCE_COUNT, "resourceTable out of sync with ResourceType enum");
static assert(itemTemplateTable.length == ItemTemplate.max + 1, "itemTemplateTable out of sync with ItemTemplate enum");
static assert(validateEntities(entityTable).length == 0, validateEntities(entityTable));
static assert(validateEntities(featureTable).length == 0, validateEntities(featureTable));