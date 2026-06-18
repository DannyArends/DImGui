/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : syncBlockInstances;
import io : writeFile, readFile;
import jobs : jobQueue, liveJobs, blockType;
import serialization : WORLD_MAGIC;
import tile : tileToWorld, tileAbove, tileBelow, isStandable, hasStandableNeighbour;
import vector : sqDist;

struct Stockpile {
  uint id;
  string name;
  int[3][] tiles;
  bool[ResourceType] accepts;     // empty = accept all
  uint[] contents;                // stored block ids (mixed)

  bool acceptsType(ResourceType t) const { return accepts.length == 0 || accepts.get(t, false); }
}

enum subPerAxis = 4;                          // 1 / 0.25 (blockSize ratio)
enum slotsPerTile = subPerAxis^^3;            // 64

uint capacity(ref Stockpile sp) { return cast(uint)sp.tiles.length * slotsPerTile; }
bool hasFreeSlot(ref Stockpile sp) { return sp.contents.length < sp.capacity; }
void stampTiles(ref GameApp app, uint id, int[3][] tiles) { foreach(t; tiles){ app.world.stockpileAt[t] = id; } }
void clearTiles(ref GameApp app, int[3][] tiles) { foreach(t; tiles) { app.world.stockpileAt.remove(t); } }

/** One new pile from the painted preview */
void createStockpile(ref GameApp app, int[3][] tiles) {
  if(tiles.length == 0) return;
  uint id = app.world.nextStockpileID++;
  Stockpile sp = { id: id, name: format("Stockpile %d", id), tiles: tiles.dup };
  app.world.stockpiles[id] = sp;
  app.stampTiles(id, sp.tiles);
}

/** Delete a pile: spill its blocks back to the floor and clear the zone */
void removeStockpile(ref GameApp app, uint id) {
  if(auto sp = id in app.world.stockpiles) {
    foreach(i, blockID; sp.contents) { if(auto b = blockID in app.world.blocks) { b.tile = sp.tiles[i / slotsPerTile].tileAbove; } }
    app.clearTiles(sp.tiles);
    app.world.stockpiles.remove(id);
    app.syncBlockInstances();
  }
}

/** Nearest accepting pile with a free slot; returns id (or 0) and fills `tile` with a target tile */
uint findStockpileSlot(ref GameApp app, ResourceType type, int[3] from, out int[3] tile) {
  uint best = 0; float bestD = float.max;
  foreach(id, ref sp; app.world.stockpiles) {
    if(!sp.acceptsType(type)) continue;
    uint pending = app.pendingStores(id);
    if(sp.contents.length + pending >= sp.capacity) continue;
    foreach(t; sp.tiles) {
      if(!app.world.hasStandableNeighbour(t.tileAbove)) continue;   // reachable to stand beside/on
      auto d = sqDist(from, t);
      if(d < bestD) { bestD = d; best = id; tile = t; }
    }
  }
  return best;
}

uint pendingStores(ref GameApp app, uint stockpileID) {
  return cast(uint)app.liveJobs("Store").count!((ref j) {
    auto id = j.targetTile in app.world.stockpileAt;
    return(id !is null && *id == stockpileID);
  });
}

void storeBlockAt(ref GameApp app, int[3] tile, uint blockID) {
  if(auto id = tile in app.world.stockpileAt) app.storeBlock(*id, blockID);
}

/** Park a carried block into a pile */
void storeBlock(ref GameApp app, uint stockpileID, uint blockID) {
  if(auto sp = stockpileID in app.world.stockpiles) {
    if(!hasFreeSlot(*sp)) return;
    sp.contents ~= blockID;
    if(auto b = blockID in app.world.blocks) b.tile = storedTile;
  }
}

bool acceptedByHolder(ref GameApp app, uint blockID, ResourceType type) {
  foreach(ref sp; app.world.stockpiles){ if(sp.contents.canFind(blockID)) { return sp.acceptsType(type); } }
  return false;
}

/** Anti-reshuffle: a block already in an accepting pile is settled */
bool isSettled(ref GameApp app, uint blockID, ResourceType type) {
  foreach(ref sp; app.world.stockpiles) { if(sp.contents.canFind(blockID)){ return sp.acceptsType(type); } }  // verdict from the HOLDER
  return false;                                                     // not in any pile -> not settled
}

uint countOf(ref GameApp app, ref Stockpile sp, ResourceType t) {
  uint n = 0;
  foreach(id; sp.contents){ if(app.blockType(id) == t) { n++; } }
  return n;
}

bool withdrawBlock(ref GameApp app, uint blockID) {
  foreach(ref sp; app.world.stockpiles) {
    auto idx = sp.contents.countUntil(blockID);
    if(idx >= 0) { sp.contents = sp.contents.remove(idx); return true; }
  }
  return false;
}

int[3] storedTileOf(ref GameApp app, uint blockID) {
  foreach(ref sp; app.world.stockpiles) {
    auto idx = sp.contents.countUntil(blockID);
    if(idx >= 0){ return(sp.tiles[idx / slotsPerTile]); }
  }
  return(noTile);
}

/** Sub-cell world offset for the n-th block in a tile */
float[3] subCellOffset(ref World world, uint slot) {
  immutable float bs = world.blockSize, half = world.tileSize * 0.5f;
  immutable uint sx = slot % subPerAxis, sy = (slot / subPerAxis) % subPerAxis, sz = slot / (subPerAxis^^2);
  return [(sx + 0.5f) * bs - half, sy * bs, (sz + 0.5f) * bs - half];
}

/** Serialize all stockpiles to one file (records + packed name/tiles/accepts/contents). */
void saveStockpiles(ref GameApp app) {
  if(app.world.stockpiles.length == 0) return;
  ubyte[] blob;
  void put(uint[] xs) { blob ~= (cast(ubyte*)xs.ptr)[0 .. xs.length * uint.sizeof]; }

  put([cast(uint)WORLD_MAGIC, app.world.nextStockpileID, cast(uint)app.world.stockpiles.length]);
  foreach(id, ref sp; app.world.stockpiles) {
    uint[] acc;
    foreach(t, on; sp.accepts) if(on) acc ~= cast(uint)t;
    put([sp.id, cast(uint)sp.name.length, cast(uint)sp.tiles.length, cast(uint)acc.length, cast(uint)sp.contents.length]);
    blob ~= cast(ubyte[])sp.name.dup;
    blob ~= cast(ubyte[])sp.tiles;
    put(acc);
    put(sp.contents);
  }
  writeFile(app.world.stockpilePath(), cast(char[])blob);
}

/** Restore stockpiles + rebuild stockpileAt. Call after loadBlocks (contents reference block ids). */
void loadStockpiles(ref GameApp app) {
  auto raw = cast(ubyte[])readFile(app.world.stockpilePath());
  if(raw.length < 12) return;
  size_t off = 0;
  bool need(size_t n) { return off + n <= raw.length; }
  uint[] take(size_t n) { auto s = cast(uint[])raw[off .. off + n*uint.sizeof].dup; off += n*uint.sizeof; return s; }

  auto hdr = take(3);
  if(hdr[0] != WORLD_MAGIC) { SDL_Log("loadStockpiles: bad magic"); return; }
  app.world.nextStockpileID = hdr[1];
  uint count = hdr[2];

  foreach(_; 0 .. count) {
    if(!need(5 * uint.sizeof)) { SDL_Log("loadStockpiles: truncated rec"); return; }
    auto r = take(5);                       // id, nameLen, tileCount, acceptCount, contentCount
    size_t nameN = r[1], tilesN = r[2] * int[3].sizeof;
    if(!need(nameN + tilesN + (r[3] + r[4]) * uint.sizeof)) { SDL_Log("loadStockpiles: truncated body"); return; }

    string name = cast(string)(cast(char[])raw[off .. off + nameN]).idup; off += nameN;
    auto tiles = (cast(int[3][])raw[off .. off + tilesN]).dup; off += tilesN;
    auto acc = take(r[3]);
    auto contents = take(r[4]);

    Stockpile sp = { id: r[0], name: name, tiles: tiles, contents: contents };
    foreach(t; acc) sp.accepts[cast(ResourceType)t] = true;
    app.world.stockpiles[r[0]] = sp;
    app.stampTiles(r[0], sp.tiles);
  }
  SDL_Log("loadStockpiles: %d piles", cast(int)app.world.stockpiles.length);
}
