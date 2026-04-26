/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import io : readFile, writeFile;
import inventory : deriveInventory;
import matrix : translate, multiply, scale;
import world : noTile, WORLD_MAGIC;

struct BlockData { int[3] tile; uint tileType; }
struct BlockFallData {
  size_t idx;
  float[2] state;  /// [y, v]

  @property @nogc float y()     nothrow { return state[0]; }
  @property @nogc float v()     nothrow { return state[1]; }
  @property @nogc void y(float val)     nothrow { state[0] = val; }
  @property @nogc void v(float val)     nothrow { state[1] = val; }
}

class Blocks : Cube {
  int[3][] tiles;           /// Tile of instances
  BlockFallData[] falling;  /// All state related to falling blocks

  this() {
    super();
    instancedMesh = true;
    instances = [];
    geometry = (){ return "Blocks"; };
  }
}

/** Save blocks dropped */
void saveBlocks(ref App app) {
  if(app.world.blocks is null) return;
  BlockData[] data;
  foreach(i, tile; app.world.blocks.tiles) { data ~= BlockData(tile, app.world.blocks.instances[i].meshdef[0]); }
  uint[2] header = [WORLD_MAGIC, cast(uint)data.length];
  writeFile(app.world.blocksPath(), cast(char[])(cast(ubyte[])header ~ cast(ubyte[])data));
}

/** Load blocks dropped */
void loadBlocks(ref App app) {
  app.world.blocks = new Blocks();
  app.objects ~= app.world.blocks;
  auto raw = readFile(app.world.blocksPath());
  if(raw.length < uint[2].sizeof) return;
  if((cast(uint[])raw)[0] != WORLD_MAGIC) { SDL_Log("loadDroppedBlocks: invalid magic"); return; }
  auto data = cast(BlockData[])raw[uint[2].sizeof..$].dup;
  foreach(ref b; data) { app.spawnBlock(b.tile, cast(TileType)b.tileType); }
  foreach(tile; app.world.blocks.tiles) app.world.pendingUnsettle ~= tile;
  SDL_Log("loadBlocks: %d blocks (%d pending unsettle)", app.world.blocks.tiles.length, app.world.pendingUnsettle.length);
}

@nogc pure bool hasBlocks(ref App app, TileType tt) nothrow {
  if(app.world.blocks is null) return false;
  return app.world.blocks.instances.any!(i => i.meshdef[0] == cast(uint)tt);
}

/** Find the closest dropped block of the given TileType to the dwarf, returns tile or [int.min,0,0] */
int[3] findFreeBlock(ref App app, int[3] dwarfTile, TileType tt = TileType.None) {
  if(app.world.blocks is null) return noTile;
  int[3] best = noTile;
  float bestDist = float.max;
  foreach(i, tile; app.world.blocks.tiles) {
    if(tt != TileType.None && app.world.blocks.instances[i].meshdef[0] != cast(uint)tt) continue;
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
  auto wp = app.world.tileToWorld(tile);
  wp[1] -= app.world.blockOffset;
  return Instance([cast(uint)tt, cast(uint)tt], translate(wp).multiply(scale([app.world.blockSize, app.world.blockSize, app.world.blockSize])));
}

/** Spawn a dropped block */
void spawnBlock(ref App app, int[3] tile, TileType tt) {
  if(app.world.blocks is null) {
    app.world.blocks = new Blocks();
    app.objects ~= app.world.blocks;
  }
  app.world.blocks.tiles ~= tile;
  app.world.blocks.instances ~= app.toDropInstance(tile, tt);
  app.world.blocks.buffers[INSTANCE] = false;
  app.deriveInventory();
}

@nogc pure bool isAbove(int[3] tile, int[3] other) nothrow { return tile[0] == other[0] && tile[2] == other[2] && tile[1] > other[1]; }

/** Check blocks above a mined tile to see if they go falling */
void unsettleBlocks(const World world, ref Blocks blocks, int[3] minedTile) {
  if(blocks is null) return;
  foreach(i, tile; blocks.tiles) {
    if(tile[0] != minedTile[0] || tile[2] != minedTile[2] || tile[1] < minedTile[1]) continue;
    if(!blocks.falling.any!(f => f.idx == i)) {
      blocks.falling ~= BlockFallData(i, [world.tileToWorld(tile)[1] - world.blockOffset(), 0.0f]);
    }
  }
}

/** Update falling blocks */
void settleBlocks(const World world, ref Blocks blocks, float dt) {
  if(blocks is null || blocks.falling.length == 0) return;
  bool changed = false;
  blocks.falling = blocks.falling.filter!((ref f) {
    f.v = f.v + 0.125f * dt;
    f.y = f.y - f.v * dt;
    if(f.idx >= blocks.tiles.length) return(false); // Done with falling
    int[3] tile = blocks.tiles[f.idx];
    int landTileY = world.surfaceAt(tile[0], tile[1] - 1, tile[2]);
    float landY = world.tileToWorld([tile[0], landTileY + 1, tile[2]])[1] - world.blockOffset;
    if(f.y <= landY) {
      blocks.tiles[f.idx] = [tile[0], landTileY+1, tile[2]];
      blocks.instances[f.idx].matrix[13] = world.tileToWorld(blocks.tiles[f.idx])[1] - world.blockOffset;
      changed = true;
      return(false); // Done with falling
    }
    blocks.instances[f.idx].matrix[13] = f.y;
    changed = true;
    return(true); // Still falling
  }).array;
  if(changed) blocks.buffers[INSTANCE] = false;
}
