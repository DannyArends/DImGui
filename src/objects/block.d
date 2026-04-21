/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import io : readFile, writeFile;
import inventory : deriveInventory;
import world : tileToWorld, WORLD_MAGIC;

struct BlockData { int[3] tile; uint tileType; }

class Blocks : Cube {
  int[3][] tiles;

  this() {
    super();
    instancedMesh = true;
    instances = [];
    geometry = (){ return "DroppedBlocks"; };
  }
}

/** Save blocks dropped */
void saveDroppedBlocks(ref App app) {
  if(app.world.droppedBlocks is null) return;
  auto blocks = app.world.droppedBlocks;
  BlockData[] data;
  foreach(i, tile; blocks.tiles) { data ~= BlockData(tile, blocks.instances[i].meshdef[0]); }
  uint[2] header = [WORLD_MAGIC, cast(uint)data.length];
  writeFile(app.world.droppedBlocksPath(), cast(char[])(cast(ubyte[])header ~ cast(ubyte[])data));
}

/** Load blocks dropped */
void loadDroppedBlocks(ref App app) {
  app.world.droppedBlocks = new Blocks();
  app.objects ~= app.world.droppedBlocks;
  auto raw = readFile(app.world.droppedBlocksPath());
  if(raw.length < uint[2].sizeof) return;
  if((cast(uint[])raw)[0] != WORLD_MAGIC) { SDL_Log("loadDroppedBlocks: invalid magic"); return; }
  auto data = cast(BlockData[])raw[uint[2].sizeof..$].dup;
  foreach(ref b; data) { app.spawnDroppedBlock(b.tile, cast(TileType)b.tileType); }
  SDL_Log("loadDroppedBlocks: %d blocks", app.world.droppedBlocks.tiles.length);
}

/** Find the closest dropped block of the given TileType to the dwarf, returns tile or [int.min,0,0] */
int[3] findFreeDroppedBlock(ref App app, TileType tt, int[3] dwarfTile) {
  import jobs : jobQueue;
  if(app.world.droppedBlocks is null) return [int.min, 0, 0];
  int[3] best = [int.min, 0, 0];
  float bestDist = float.max;
  foreach(i, tile; app.world.droppedBlocks.tiles) {
    if(app.world.droppedBlocks.instances[i].meshdef[0] != cast(uint)tt) continue;
    // skip if already reserved in queue
    bool reserved = false;
    foreach(j; jobQueue) { if(j.prereqs.length > 0 && j.prereqs[0].targetTile == tile) { reserved = true; break; } }
    if(reserved) continue;
    float dist = abs(tile[0] - dwarfTile[0]) + abs(tile[2] - dwarfTile[2]);
    if(dist < bestDist) { bestDist = dist; best = tile; }
  }
  return best;
}

/** Create a drop instance */
Instance toDropInstance(ref App app, int[3] tile, TileType tt) {
  float ts = app.world.tileSize * 0.25f;
  float th = app.world.tileHeight * 0.25f;
  auto wp = app.tileToWorld(tile);
  wp[1] -= (app.world.tileHeight - th) * 0.5f;
  return Instance(cast(uint)tt, [ts,0,0, 0,th,0, 0,0,ts, wp[0],wp[1],wp[2]]);
}

/** Spawn a dropped block */
void spawnDroppedBlock(ref App app, int[3] tile, TileType tt) {
  if(app.world.droppedBlocks is null) {
    app.world.droppedBlocks = new Blocks();
    app.objects ~= app.world.droppedBlocks;
  }
  app.world.droppedBlocks.tiles ~= tile;
  app.world.droppedBlocks.instances ~= app.toDropInstance(tile, tt);
  app.world.droppedBlocks.buffers[INSTANCE] = false;
  app.deriveInventory();
}

