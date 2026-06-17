/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import vector : sqDist;
import tile : tileToWorld;

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

/** One new pile from the painted preview */
void createStockpile(ref GameApp app, int[3][] tiles) {
  if(tiles.length == 0) return;
  uint id = app.world.nextStockpileID++;
  Stockpile sp = { id: id, name: format("Stockpile %d", id), tiles: tiles.dup };
  app.world.stockpiles[id] = sp;
  foreach(t; tiles) app.world.stockpileAt[t] = id;
}

/** Nearest accepting pile with a free slot; returns id (or 0) and fills `tile` with a target tile */
uint findStockpileSlot(ref GameApp app, ResourceType type, int[3] from, out int[3] tile) {
  uint best = 0; float bestD = float.max;
  foreach(id, ref sp; app.world.stockpiles) {
    if(!sp.acceptsType(type) || !sp.hasFreeSlot) continue;
    foreach(t; sp.tiles) {
      auto d = sqDist(from, t); 
      if(d < bestD) { bestD = d; best = id; tile = t; }   // any tile of the pile; sub-slot chosen at store time
    }
  }
  return best;
}

void storeBlockAt(ref GameApp app, int[3] tile, uint blockID) {
  if(auto id = tile in app.world.stockpileAt) app.storeBlock(*id, blockID);
}

/** Park a carried block into a pile */
void storeBlock(ref GameApp app, uint stockpileID, uint blockID) {
  if(auto sp = stockpileID in app.world.stockpiles) {
    sp.contents ~= blockID;
    if(auto b = blockID in app.world.blocks) b.tile = storedTile;
  }
}

/** Anti-reshuffle: a block already in an accepting pile is settled */
bool isSettled(ref GameApp app, uint blockID, ResourceType type) {
  foreach(ref sp; app.world.stockpiles)
    if(sp.acceptsType(type) && sp.contents.canFind(blockID)) return true;
  return false;
}

/** Sub-cell world offset for the n-th block in a tile */
float[3] subCellOffset(ref GameApp app, uint slot) {
  float bs = app.world.blockSize;
  uint sx = slot % subPerAxis, sy = (slot / subPerAxis) % subPerAxis, sz = slot / (subPerAxis*subPerAxis);
  return [(sx + 0.5f) * bs - app.world.tileSize * 0.5f, sy * bs, (sz + 0.5f) * bs - app.world.tileSize * 0.5f];
}