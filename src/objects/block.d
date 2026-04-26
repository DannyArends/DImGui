/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import io : readFile, writeFile;
import inventory : deriveInventory;
import matrix : translate, multiply, scale;
import world : tileToWorld, WORLD_MAGIC;

struct BlockData { int[3] tile; uint tileType; }
struct BlockFallData {
  size_t idx;
  float[2] state;  /// [y, v]

  @property @nogc float y() nothrow { return state[0]; }
  @property @nogc float v() nothrow { return state[1]; }
  @property @nogc void y(float y) nothrow { state[0] = y; }
  @property @nogc void v(float v) nothrow { state[1] = v; }
}

class Blocks : Cube {
  int[3][] tiles;           /// Tile of instances
  BlockFallData[] falling;  /// All state related to falling blocks

  this() {
    super();
    instancedMesh = true;
    instances = [];
    geometry = (){ return "DroppedBlocks"; };
  }
}

/** Save blocks dropped */
void saveBlocks(ref App app) {
  if(app.world.droppedBlocks is null) return;
  auto blocks = app.world.droppedBlocks;
  BlockData[] data;
  foreach(i, tile; blocks.tiles) { data ~= BlockData(tile, blocks.instances[i].meshdef[0]); }
  uint[2] header = [WORLD_MAGIC, cast(uint)data.length];
  writeFile(app.world.droppedBlocksPath(), cast(char[])(cast(ubyte[])header ~ cast(ubyte[])data));
}

/** Load blocks dropped */
void loadBlocks(ref App app) {
  app.world.droppedBlocks = new Blocks();
  app.objects ~= app.world.droppedBlocks;
  auto raw = readFile(app.world.droppedBlocksPath());
  if(raw.length < uint[2].sizeof) return;
  if((cast(uint[])raw)[0] != WORLD_MAGIC) { SDL_Log("loadDroppedBlocks: invalid magic"); return; }
  auto data = cast(BlockData[])raw[uint[2].sizeof..$].dup;
  foreach(ref b; data) { app.spawnBlock(b.tile, cast(TileType)b.tileType); }
  SDL_Log("loadDroppedBlocks: %d blocks", app.world.droppedBlocks.tiles.length);
}

@nogc pure bool hasBlocks(ref App app, TileType tt) nothrow {
  if(app.world.droppedBlocks is null) return false;
  return app.world.droppedBlocks.instances.any!(i => i.meshdef[0] == cast(uint)tt);
}

/** Find the closest dropped block of the given TileType to the dwarf, returns tile or [int.min,0,0] */
int[3] findFreeBlock(ref App app, TileType tt, int[3] dwarfTile) {
  if(app.world.droppedBlocks is null) return [int.min, 0, 0];
  int[3] best = [int.min, 0, 0];
  float bestDist = float.max;
  foreach(i, tile; app.world.droppedBlocks.tiles) {
    if(app.world.droppedBlocks.instances[i].meshdef[0] != cast(uint)tt) continue;
    // only skip blocks already on an active dwarf's jobStack
    bool reserved = false;
    foreach(o; app.objects) {
      auto d = cast(Dwarf)o;
      if(d is null) continue;
      foreach(j; d.jobStack) { if(j.targetTile == tile) { reserved = true; break; } }
      if(reserved) break;
    }
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
  return Instance([cast(uint)tt, cast(uint)tt], translate(wp).multiply(scale([ts, th, ts])));
}

/** Spawn a dropped block */
void spawnBlock(ref App app, int[3] tile, TileType tt) {
  if(app.world.droppedBlocks is null) {
    app.world.droppedBlocks = new Blocks();
    app.objects ~= app.world.droppedBlocks;
  }
  app.world.droppedBlocks.tiles ~= tile;
  app.world.droppedBlocks.instances ~= app.toDropInstance(tile, tt);
  app.world.droppedBlocks.buffers[INSTANCE] = false;
  app.deriveInventory();
}

@nogc pure bool isAbove(int[3] tile, int[3] other) nothrow { return tile[0] == other[0] && tile[2] == other[2] && tile[1] > other[1]; }

/** Check blocks above a mined tile to see if they go falling */
void unsettleBlocksAbove(ref App app, int[3] minedTile) {
  auto db = app.world.droppedBlocks;
  if(db is null) return;
  foreach(i, tile; db.tiles) {
    int[3] below = [tile[0], tile[1] - 1, tile[2]];
    if(below == minedTile && !db.falling.any!(f => f.idx == i))
      db.falling ~= BlockFallData(i, [app.toDropInstance(tile, TileType.None).matrix[13], 0.0f]);
  }
}

/** Update falling blocks */
void settleBlocks(ref App app, float dt) {
  auto db = app.world.droppedBlocks;
  if(db is null || db.falling.length == 0) return;
  bool changed = false;
  db.falling = db.falling.filter!((ref f) {
    f.v = f.v + 0.005f * (dt / 100.0f);
    f.y = f.y - f.v * (dt / 100.0f);
    float landY = app.toDropInstance(db.tiles[f.idx], TileType.None).matrix[13] - app.world.tileHeight;
    if(f.y <= landY) {
      db.tiles[f.idx][1] -= 1;
      db.instances[f.idx] = app.toDropInstance(db.tiles[f.idx], cast(TileType)db.instances[f.idx].meshdef[0]);
      changed = true;
      return false;
    }
    db.instances[f.idx].matrix[13] = f.y;
    changed = true;
    return true;
  }).array;
  if(changed) db.buffers[INSTANCE] = false;
}
