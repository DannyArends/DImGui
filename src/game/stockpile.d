/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : blockType, syncBlockInstances;
import io : writeFile, readFile;
import jobs : jobQueue, liveJobs, Reach;
import serialization : WORLD_MAGIC;
import pathfinding : findGoalTile;
import tile : tileToWorld, tileAbove, tileBelow, isStandable, hasStandableNeighbour;
import vector : sqDist;

struct Stockpile {
  uint id;
  string name;
  int[3][] tiles;
  bool[ResourceType] accepts;     // empty = accept all
  uint[] contents;                // stored block ids (mixed)

  /** True if this pile accepts 't'; an empty 'accepts' set means accept everything. */
  @nogc bool acceptsType(ResourceType t) const { auto p = t in accepts; return accepts.length == 0 || (p !is null && *p); }
}

struct StockpileField {
  Stockpile[uint] byId;
  alias byId this;
  uint[int[3]] at;
  uint nextID = 1;
}

enum subPerAxis = 4;                          // 1 / 0.25 (blockSize ratio)
enum slotsPerTile = subPerAxis^^3;            // 64
enum uint emptySlot = uint.max;

/** Total block slots across all of the pile's tiles */
@nogc uint capacity(const Stockpile sp) nothrow { return cast(uint)sp.tiles.length * slotsPerTile; }

/** "True if the pile has room for another block */
@nogc bool hasFreeSlot(const Stockpile sp) nothrow { return sp.contents.countUntil(emptySlot) >= 0 || sp.contents.length < sp.capacity; }

/** Mark each tile as belonging to stockpile `id` in the world's tile to pile index */
void stampTiles(ref World world, uint id, int[3][] tiles) { foreach(t; tiles){ world.stockpiles.at[t] = id; } }

/** Remove the given tiles from the world's tile to pile index */
void clearTiles(ref World world, int[3][] tiles) { foreach(t; tiles) { world.stockpiles.at.remove(t); } }

/** One new pile from the painted preview */
void createStockpile(ref World world, int[3][] tiles) {
  if(tiles.length == 0) return;
  uint id = world.stockpiles.nextID++;
  world.stockpiles[id] = Stockpile(id: id, name: format("Stockpile %d", id), tiles: tiles.dup);
  world.stampTiles(id, world.stockpiles[id].tiles);
}

/** Delete a pile: spill its blocks back to the floor and clear the zone */
void removeStockpile(ref World world, uint id) {
  if(auto sp = id in world.stockpiles) {
    foreach(i, blockID; sp.contents) { if(auto b = blockID in world.drops) { b.tile = sp.tiles[i / slotsPerTile].tileAbove; } }
    world.clearTiles(sp.tiles);
    world.stockpiles.byId.remove(id);
    world.drops.dirty = true;
  }
}

/** Nearest accepting pile with a free slot; returns id (or 0) and fills `tile` with a target tile */
uint findStockpileSlot(const World world, ResourceType type, int[3] from, out int[3] tile) {
  uint best = 0; float bestD = float.max;
  foreach(id, sp; world.stockpiles) {
    if(!sp.acceptsType(type)) continue;
    uint pending = world.pendingStores(id);
    if(sp.contents.length + pending >= sp.capacity) continue;
    foreach(t; sp.tiles) {
      auto above = t.tileAbove;
      if(world.findGoalTile(above, from, Reach.Adjacent) == noTile) continue;
      auto d = sqDist(from, above);
      if(d < bestD) { bestD = d; best = id; tile = above; }
    }
  }
  return best;
}

/** Count of in-flight Store jobs already targeting this pile, reserved capacity not yet filled */
uint pendingStores(const World world, uint stockpileID) {
  return cast(uint)world.liveJobs("Store").count!((ref j) {
    auto id = j.targetTile.tileBelow in world.stockpiles.at;
    return(id !is null && *id == stockpileID);
  });
}

/** Park a carried block into a pile */
void storeBlockAt(ref World world, int[3] tile, uint blockID) {
  if(auto idp = tile.tileBelow in world.stockpiles.at) {
    if(auto sp = *idp in world.stockpiles) {
      if(!hasFreeSlot(*sp)) return;
      ptrdiff_t slot = sp.contents.countUntil(emptySlot);
      if(slot < 0) { slot = sp.contents.length; sp.contents ~= emptySlot; }
      if(slot >= capacity(*sp)) return;
      sp.contents[slot] = blockID;
      if(auto b = blockID in world.drops) { b.tile = storedTile; b.fall = Fall.init; }
    }
  }
}

/** True if 'blockID' already sits in a pile that accepts 'type', as in it doesn't need (re)storing */
bool acceptedByHolder(const Stockpile[uint] stockpiles, uint blockID, ResourceType type) {
  foreach(sp; stockpiles){ if(sp.contents.canFind(blockID)) { return sp.acceptsType(type); } }
  return false;
}

/** Number of stored blocks of type 't' in the pile */
uint countOf(const Stockpile sp, const Block[uint] drops, ResourceType t) {
  uint n = 0;
  foreach(id; sp.contents){ if(drops.blockType(id) == t) { n++; } }
  return n;
}

/** Remove 'blockID' from whichever pile holds it, returns false if it wasn't stored */
bool withdrawBlock(ref World world, uint blockID) {
  foreach(ref sp; world.stockpiles) {
    auto idx = sp.contents.countUntil(blockID);
    if(idx >= 0) { sp.contents = sp.contents.remove(idx); return(true); }
  }
  return(false);
}

/** World tile of the pile cell holding 'blockID', or noTile if not stored */
@nogc int[3] storedTileOf(const World world, uint blockID) {
  foreach(sp; world.stockpiles) {
    auto idx = sp.contents.countUntil(blockID);
    if(idx >= 0){ return(sp.tiles[idx / slotsPerTile]); }
  }
  return(noTile);
}

/** Sub-cell world offset for the n-th block in a tile */
float[3] subCellOffset(const World world, uint slot) {
  immutable float bs = world.blockSize, half = world.tileSize * 0.5f;
  immutable uint sx = slot % subPerAxis, sy = (slot / subPerAxis) % subPerAxis, sz = slot / (subPerAxis^^2);
  return [(sx + 0.5f) * bs - half, sy * bs, (sz + 0.5f) * bs - half];
}

/** Serialize all stockpiles to one file (records + packed name/tiles/accepts/contents) */
void saveStockpiles(const World world) {
  if(world.stockpiles.length == 0) return;
  ubyte[] blob;
  void put(const(uint[]) xs) { blob ~= (cast(ubyte*)xs.ptr)[0 .. xs.length * uint.sizeof]; }

  put([cast(uint)WORLD_MAGIC, world.stockpiles.nextID, cast(uint)world.stockpiles.length]);
  foreach(id, ref sp; world.stockpiles) {
    uint[] acc;
    foreach(t, on; sp.accepts) if(on) acc ~= cast(uint)t;
    put([sp.id, cast(uint)sp.name.length, cast(uint)sp.tiles.length, cast(uint)acc.length, cast(uint)sp.contents.length]);
    blob ~= cast(ubyte[])sp.name.dup;
    blob ~= cast(ubyte[])sp.tiles;
    put(acc);
    put(sp.contents);
  }
  writeFile(world.stockpilePath(), cast(char[])blob);
}

/** Restore stockpiles + rebuild stockpileAt. Call after loadBlocks (contents reference block ids) */
void loadStockpiles(ref World world) {
  auto raw = cast(ubyte[])readFile(world.stockpilePath());
  if(raw.length < 12) return;
  size_t off = 0;
  bool need(size_t n) { return off + n <= raw.length; }
  uint[] take(size_t n) { auto s = cast(uint[])raw[off .. off + n*uint.sizeof].dup; off += n*uint.sizeof; return s; }

  auto hdr = take(3);
  if(hdr[0] != WORLD_MAGIC) { SDL_Log("loadStockpiles: bad magic"); return; }
  world.stockpiles.nextID = hdr[1];
  uint count = hdr[2];

  foreach(_; 0 .. count) {
    if(!need(5 * uint.sizeof)) { SDL_Log("loadStockpiles: truncated rec"); return; }
    auto r = take(5); // [id, nameLen, tileCount, acceptCount, contentCount]
    size_t nameN = r[1], tilesN = r[2] * int[3].sizeof;
    if(!need(nameN + tilesN + (r[3] + r[4]) * uint.sizeof)) { SDL_Log("loadStockpiles: truncated body"); return; }

    string name = cast(string)(cast(char[])raw[off .. off + nameN]).idup; off += nameN;
    auto tiles = (cast(int[3][])raw[off .. off + tilesN]).dup; off += tilesN;
    auto acc = take(r[3]);
    auto contents = take(r[4]);

    Stockpile sp = { id: r[0], name: name, tiles: tiles, contents: contents };
    foreach(t; acc) sp.accepts[cast(ResourceType)t] = true;
    world.stockpiles[r[0]] = sp;
    world.stampTiles(r[0], sp.tiles);
  }
  SDL_Log("loadStockpiles: %d piles", cast(int)world.stockpiles.length);
}
