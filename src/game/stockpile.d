/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : itemOf;
import jobs : liveJobs, Reach;
import lattice : tileBelow, tileAbove;
import pathfinding : findGoalTile;
import resources : isCraft;
import vector : sqDist;

struct Stockpile {
  uint id;
  string name;
  int[3][] tiles;
  bool[Item] accepts;             /// empty = accept all; keyed on acceptKey
  uint[] contents;                /// stored block ids (mixed)

  /** True if this pile accepts `it`; an empty `accepts` set means accept everything. */
  @nogc bool acceptsItem(Item it) const { auto p = it.acceptKey in accepts; return accepts.length == 0 || (p !is null && *p); }
}

/** Canonical stockpile key: what matters for storage — a craft by its template, a raw item by its material; fill state (contents/amount) dropped. */
@nogc pure Item acceptKey(Item it) nothrow { return it.isCraft ? Item(it.shape) : Item(ItemTemplate.None, it.material); }

struct StockpileField {
  Stockpile[uint] byId;
  alias byId this;
  LatticeMap!uint at;
  uint nextID = 1;
}

enum subSize = 0.25f;                         /// sub-block cell size (fraction of a tile)
enum subPerAxis = cast(int)(1.0f / subSize);  /// cells per tile axis
enum slotsPerTile = subPerAxis ^^ 3;          /// subPerAxis cubed
enum uint emptySlot = uint.max;

/** Total block slots across all of the pile's tiles */
@nogc uint capacity(const Stockpile sp) nothrow { return cast(uint)sp.tiles.length * slotsPerTile; }

/** True if the pile has room for another block, counting in-flight stores. */
@nogc bool hasFreeSlot(const Stockpile sp, uint pending = 0) nothrow {
  return sp.contents.countUntil(emptySlot) >= 0 || sp.contents.length + pending < sp.capacity;
}

/** Mark each tile as belonging to stockpile `id` in the world's tile to pile index */
void stampTiles(ref World world, uint id, int[3][] tiles) { foreach(t; tiles){ world.stockpiles.at[t] = id; } }

/** Remove the given tiles from the world's tile to pile index */
void clearTiles(ref World world, int[3][] tiles) { foreach(t; tiles) { world.stockpiles.at.remove(t); } }

/** The block's compacted position within its pile: count of non-empty slots before it. */
@nogc uint rankOf(const Stockpile sp, size_t slot) nothrow { return cast(uint)sp.contents[0 .. slot].count!(id => id != emptySlot); }

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
    for(size_t i = 0, rank = 0; i < sp.contents.length; i++) {
      if(sp.contents[i] == emptySlot) continue;
      if(auto b = sp.contents[i] in world.drops) { b.tile = sp.tiles[rank / slotsPerTile].tileAbove; }
      rank++;
    }
    world.clearTiles(sp.tiles);
    world.stockpiles.byId.remove(id);
    world.drops.dirty = true;
  }
}

/** Nearest accepting pile with a free slot; returns id (or 0) and fills `tile` with a target tile */
uint findStockpileSlot(const World world, Item it, int[3] from, out int[3] tile) {
  uint best = 0; float bestD = float.max;
  foreach(id, sp; world.stockpiles) {
    if(!sp.acceptsItem(it)) continue;
    if(!sp.hasFreeSlot(world.pendingStores(id))) continue;
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
      ptrdiff_t slot = sp.contents.countUntil(emptySlot);   // reuse a hole if there is one
      if(slot < 0) {
        if(sp.contents.length >= capacity(*sp)) return;     // full: refuse BEFORE growing
        slot = sp.contents.length;
        sp.contents ~= emptySlot;
      }
      sp.contents[slot] = blockID;
      if(auto b = blockID in world.drops) { b.tile = storedTile; b.fall = Fall.init; }
    }
  }
}

/** True if 'blockID' already sits in a pile that accepts 'type', as in it doesn't need (re)storing */
bool acceptedByHolder(const Stockpile[uint] stockpiles, uint blockID, Item it) {
  foreach(sp; stockpiles){ if(sp.contents.canFind(blockID)) { return sp.acceptsItem(it); } }
  return false;
}

/** Number of stored blocks of type 't' in the pile */
uint countOf(const Stockpile sp, const Drops drops, Item key) {
  uint n = 0;
  foreach(id; sp.contents){ if(drops.itemOf(id).acceptKey == key) { n++; } }
  return n;
}

/** Remove 'blockID' from whichever pile holds it, returns false if it wasn't stored */
bool withdrawBlock(ref World world, uint blockID) {
  foreach(ref sp; world.stockpiles) {
    auto idx = sp.contents.countUntil(blockID);
    if(idx >= 0) { sp.contents[idx] = emptySlot; return(true); }
  }
  return(false);
}

/** World tile of the pile cell holding 'blockID', or noTile if not stored */
@nogc int[3] storedTileOf(const World world, uint blockID) {
  foreach(sp; world.stockpiles) {
    auto idx = sp.contents.countUntil(blockID);
    if(idx >= 0){ auto ti = sp.rankOf(idx) / slotsPerTile; return(sp.tiles[ti]); }
  }
  return(noTile);
}

/** Sub-cell world offset for the n-th block in a tile */
float[3] subCellOffset(const World world, uint slot) {
  assert(slot < slotsPerTile, "subCellOffset: slot out of sub-cell range");
  immutable float bs = world.blockSize, half = world.tileSize * 0.5f;
  immutable uint sx = slot % subPerAxis, sy = (slot / subPerAxis) % subPerAxis, sz = slot / (subPerAxis^^2);
  return [(sx + 0.5f) * bs - half, sy * bs, (sz + 0.5f) * bs - half];
}

/** Serialize all stockpiles to one file (records + packed name/tiles/accepts/contents) */
ubyte[] saveStockpiles(const World world) {
  ubyte[] blob;
  void put(T)(const(T)[] xs) { blob ~= (cast(ubyte*)xs.ptr)[0 .. xs.length * T.sizeof]; }

  put([world.stockpiles.nextID, cast(uint)world.stockpiles.length]);
  foreach(id, ref sp; world.stockpiles) {
    Item[] acc;
    foreach(k, on; sp.accepts) if(on) acc ~= k;
    put([sp.id, cast(uint)sp.name.length, cast(uint)sp.tiles.length, cast(uint)acc.length, cast(uint)sp.contents.length]);
    put(sp.name); put(sp.tiles); put(acc); put(sp.contents);
  }
  return blob;
}

/** Restore stockpiles + rebuild stockpileAt. Call after loadBlocks (contents reference block ids) */
void loadStockpiles(ref World world, ubyte[] raw) {
  if(raw.length < 8) return;
  size_t off = 0;
  bool need(size_t n) { return off + n <= raw.length; }
  uint[] take(size_t n) { auto s = cast(uint[])raw[off .. off + n*uint.sizeof].dup; off += n*uint.sizeof; return s; }

  world.stockpiles.nextID = take(1)[0];
  uint count = take(1)[0];

  foreach(_; 0 .. count) {
    if(!need(5 * uint.sizeof)) { SDL_Log("loadStockpiles: truncated rec"); return; }
    auto r = take(5); // [id, nameLen, tileCount, acceptCount, contentCount]
    size_t nameN = r[1], tilesN = r[2] * int[3].sizeof;
    if(!need(nameN + tilesN + r[3]*Item.sizeof + r[4]*uint.sizeof)) { SDL_Log("loadStockpiles: truncated body"); return; }

    string name = cast(string)(cast(char[])raw[off .. off + nameN]).idup; off += nameN;
    auto tiles = (cast(int[3][])raw[off .. off + tilesN]).dup; off += tilesN;
    auto acc = (cast(Item[])raw[off .. off + r[3]*Item.sizeof]).dup; off += r[3]*Item.sizeof;
    auto contents = take(r[4]);

    Stockpile sp = { id: r[0], name: name, tiles: tiles, contents: contents };
    foreach(k; acc) sp.accepts[k] = true;
    world.stockpiles[r[0]] = sp;
    world.stampTiles(r[0], sp.tiles);
  }
  SDL_Log("loadStockpiles: %d piles", cast(int)world.stockpiles.length);
}
