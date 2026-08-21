/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import color : toColor;
import ctfe : namedField, opt, parseRawsGeneric, parseTokens, splitColon;
import lsystem : Effect, Rule, Symbol, RESERVED, lex;
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

/** Shared render tokens for any template carrying scale/offsetY/maxStack/food. Returns true if handled. */
bool parseRenderToken(T)(ref T cur, const string[] p) pure {
  switch(p[0]) {
    case "MESH": if(p.length > 1) {
      cur.mesh  = p[1];
      cur.tex3D = namedField(p, "tex3D");
      static if(__traits(hasMember, T, "tex2D")) cur.tex2D = namedField(p, "tex2D");
      static if(__traits(hasMember, T, "tex")) cur.tex = namedField(p, "tex");
      static if(__traits(hasMember, T, "texFilled")) cur.texFilled = namedField(p, "texFilled");
      static if(__traits(hasMember, T, "color")) { immutable c = namedField(p, "color"); if(c.length) cur.color = toColor(c); }
    } return true;
    case "SCALE":    cur.scale    = to!float(p[1]); return true;
    case "OFFSET_Y": cur.offsetY  = to!float(p[1]); return true;
    case "STACK":    cur.maxStack = to!int(p[1]);   return true;
    case "FOOD":     cur.food     = to!float(p[1]); return true;
    default: return false;
  }
}

ResourceT[] parseResources(string tilesRaw) pure { return parseRawsGeneric!(ResourceT, "TILE", (ref cur, p) {
  if(parseRenderToken(cur, p)) return;
  switch(p[0]) {
    case "SUBSTANCE":   cur.substance = p[1].to!Substance; break;
    case "TRAVERSABLE": cur.traverse = opt(p, 1, 1.0f); break;
    case "BUILDABLE":   cur.build = true; break;
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
    if(p.length >= 6 && p[0] == "BRUSH") {
      immutable string sub = namedField(p, "substance");
      if(sub.length == 0) continue;                         // render-only brush -> no resource variant
      immutable string member = feat ~ sub;
      if(seen.canFind(member)) continue;                    // first brush of a substance wins
      seen ~= member;
      immutable string tex = namedField(p, "texture");
      table ~= ResourceT(name: member, mesh: p[2], tex3D: tex, tex2D: tex,
                         scale: namedField(p, "dropScale", "1.0").to!float,
                         offsetY: namedField(p, "dropOffsetY", "0.0").to!float,
                         substance: sub.to!Substance,
                         source: feat.to!Source,
                         food: namedField(p, "food", "0.0").to!float);
    }
  }
  return table;
}

/** CTFE: parse items.txt into the per-template table (index 0 == ItemTemplate.None, then parallel to the enum). */
ItemTemplateT[] parseItemTemplates(string raw) pure { return parseRawsGeneric!(ItemTemplateT, "ITEM", (ref cur, p) {
  if(parseRenderToken(cur, p)) return;
  switch(p[0]) {
    case "ACCEPTS":  cur.accepts ~= p[1].to!Substance; break;
    case "HOLDS":    cur.holds   ~= p[1].to!Substance; break;
    case "CAPACITY": cur.capacity = to!uint(p[1]); break;
    default: break;
  }
})(raw, true); }

/** Parse a grammar token (AXIOM/RULE) shared by every raw template. Returns true if handled. */
bool parseGrammarToken(ref RawT x, const string[] p) pure {
  switch(p[0]) {
    case "AXIOM":         x.axiom = p[1]; return true;
    case "RULE": if(p.length >= 4){
      x.rules ~= Rule(p[1], p[2], to!uint(p[3]), opt(p, 4, int.min), opt(p, 5, int.max));
    } return true;
    case "BONE": if(p.length >= 2){ x.bones ~= LSystemBoneT(p[1]); } return true;
    case "BRUSH": if(p.length >= 5){
      LSystemBrushT b = { symbol: p[1], mesh: p[2], radius: to!float(p[3]), length: to!float(p[4]) };
      foreach(kv; p[5 .. $]) {
        immutable e = kv.indexOf('=');                 // "key=value"; bare "tint" allowed
        immutable string k = (e < 0) ? kv : kv[0 .. e];
        immutable string v = (e < 0) ? "" : kv[e + 1 .. $];
        switch(k) {
          case "substance": b.substance = v.to!Substance; break;
          case "texture":   b.texture = v; break;
          case "food":      b.food = to!float(v); break;
          case "taper":     b.taper = to!float(v); break;
          case "jitterA":   b.jitterA = to!float(v); break;
          case "jitterL":   b.jitterL = to!float(v); break;
          case "render":    b.render = to!bool(v); break;
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
    } return true;
    case "CLIP": if(p.length >= 2){
      x.clips ~= AnimClip(p[1], opt(p, 2), [], (Symbol[string]).init, opt(p, 3) == "moving", opt(p, 4, 8.0f), opt(p, 5, 25.0f));
    } return true;
    case "CRULE": if(p.length >= 4 && x.clips.length){ x.clips[$-1].rules ~= Rule(p[1], p[2], to!uint(p[3])); } return true;
    case "POSE": if(p.length >= 3 && x.clips.length){
      Symbol ps = { effect: Effect.pose, target: p[2] };
      x.clips[$-1].poses[p[1]] = ps;
    } return true;
    default: return false;
  }
}

/** One raw handler for every template: grammar tokens (via parseGrammarToken) + all domain tokens. A
    features file never emits MOVE_SPEED, a pawn file never emits HEIGHT_MIN — one parser, no drift. */
void rawHandler(ref RawT x, const string[] p) pure {
  if(parseGrammarToken(x, p)) return;
  switch(p[0]) {
    case "SPAWN_ON":         x.spawnOn ~= p[1].to!ResourceType; break;
    case "NOISE_THRESHOLD":  x.noiseThreshold = to!float(p[1]); break;
    case "HASH_SEED1":       x.hashSeed1 = to!uint(p[1]); break;
    case "HASH_SEED2":       x.hashSeed2 = to!uint(p[1]); break;
    case "HASH_MOD":         x.hashMod = to!uint(p[1]); break;
    case "HASH_REM":         x.hashRem = to!uint(p[1]); break;
    case "HEIGHT_MIN":       x.heightMin = to!uint(p[1]); break;
    case "HEIGHT_MAX":       x.heightMax = to!uint(p[1]); break;
    case "TILE_PENALTY":     x.tilePenalty = to!float(p[1]); break;
    case "PROGRESS_RATE":    x.progressRate = to!float(p[1]); break;
    case "INTERACTION":      x.interaction = p[1]; break;
    case "SOUND":            x.sound = p[1]; break;
    case "MOVE_SPEED":       x.moveSpeed = to!float(p[1]); break;
    case "HOP":              x.hop = to!float(p[1]); break;
    case "HUNGER_DECAY":     x.hungerDecay = to!float(p[1]); break;
    case "THIRST_DECAY":     x.thirstDecay = to!float(p[1]); break;
    case "DIET":             x.diet = p[1]; break;
    case "SCALE":            x.scale = to!float(p[1]); break;
    case "SCALE_VARIANCE":   x.scaleVariance = to!float(p[1]); break;
    case "OFFSET_Y":         x.offsetY = to!float(p[1]); break;
    case "FACING":           x.facing = to!float(p[1]); break;
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
private bool isControl(string t) pure { return t.length == 1 && RESERVED.canFind(t[0]); }

/** CTFE: symbols an entity/clip grammar can produce (axiom + every rule production). */
private bool[string] produced(string axiom, const Rule[] rules) pure {
  bool[string] s; foreach(t; lex(axiom)) s[t.name] = true;
  foreach(ref r; rules) foreach(t; lex(r.production)) s[t.name] = true;
  return s;
}

/** CTFE: first symbol-consistency error across all entities ("" == valid). */
string validateEntities(const RawT[] es) pure {
  foreach(ref e; es) {
    bool[string] declared; 
    foreach(ref b; e.brushes) { declared[b.symbol] = true; }
    foreach(ref b; e.bones) { declared[b.symbol] = true; }
    foreach(c, _; produced(e.axiom, e.rules)) {
      if(!isControl(c) && c !in declared && e.rules.all!(r => r.predecessor != c)){
        return e.name ~ ": body symbol '" ~ c ~ "' has no [BRUSH] or [BONE] and no [RULE]";
      }
    }
    foreach(ref cl; e.clips) {
      auto emitted = produced(cl.axiom, cl.rules);
      foreach(sym, ref pb; cl.poses) {
        if(sym !in emitted) { return e.name ~ "/" ~ cl.name ~ ": [POSE] symbol '" ~ sym ~ "' never produced by the clip"; }
        if(pb.target !in declared) { return e.name ~ "/" ~ cl.name ~ ": [POSE] target '" ~ pb.target ~ "' has no [BRUSH] or [BONE]"; }
      }
    }
  }
  return "";
}

/** CTFE: per-feature spawn membership mask indexed by ResourceType, parallel to `features`. */
private SpawnMask spawnMask(const RawT ft) pure {
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
immutable RawT[] featureTable = parseRawsGeneric!(RawT, "FEATURE", rawHandler)(import("data/raws/features.txt"));
immutable RawT[] entityTable  = parseRawsGeneric!(RawT, "ENTITY",  rawHandler)(import("data/raws/entity.txt"));

static assert(resourceTable.length == RESOURCE_COUNT, "resourceTable out of sync with ResourceType enum");
static assert(itemTemplateTable.length == ItemTemplate.max + 1, "itemTemplateTable out of sync with ItemTemplate enum");
static assert(validateEntities(entityTable).length == 0, validateEntities(entityTable));
static assert(validateEntities(featureTable).length == 0, validateEntities(featureTable));