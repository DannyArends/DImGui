/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import io : readFile, writeFile;
import inventory : deriveInventory;
import matrix : translate, multiply, scale;
import world : noTile, WORLD_MAGIC;

enum uint noBlock = uint.max;

struct Block {
  uint id;              /// Unique block ID, forever
  TileType type;        /// Block type
  int[3] tile;          /// Current tile position
  float[2] fallState;   /// [y, v] fall physics, [0,0] if not falling

  @property @nogc bool isFalling() nothrow { return fallState[1] != 0.0f; }
  @property @nogc float y()  nothrow { return fallState[0]; }
  @property @nogc float v()  nothrow { return fallState[1]; }
  @property @nogc void y(float val) nothrow { fallState[0] = val; }
  @property @nogc void v(float val) nothrow { fallState[1] = val; }
}

class Blocks : Cube {
  Block[] blocks;           /// All blocks, forever
  uint nextID = 1;          /// Next block ID

  this() {
    super();
    instancedMesh = true;
    instances = [];
    geometry = (){ return "Blocks"; };
  }
}

/** Save blocks */
void saveBlocks(ref App app) {
  if(app.world.blocks is null) return;
  uint[2] header = [WORLD_MAGIC, app.world.blocks.nextID];
  writeFile(app.world.blocksPath(), cast(char[])(cast(ubyte[])header ~ cast(ubyte[])app.world.blocks.blocks));
}

/** Load blocks */
void loadBlocks(ref App app) {
  app.world.blocks = new Blocks();
  app.objects ~= app.world.blocks;
  auto raw = readFile(app.world.blocksPath());
  if(raw.length < uint[2].sizeof) return;
  if((cast(uint[])raw)[0] != WORLD_MAGIC) { SDL_Log("loadBlocks: invalid magic"); return; }
  app.world.blocks.nextID = (cast(uint[])raw)[1];
  app.world.blocks.blocks = cast(Block[])raw[uint[2].sizeof..$].dup;
  foreach(ref b; app.world.blocks.blocks) {
    app.world.blocks.instances ~= app.toDropInstance(b.tile, b.type);
    if(b.isFalling) app.world.pendingUnsettle ~= b.tile;
  }
  app.world.blocks.buffers[INSTANCE] = false;
  SDL_Log("loadBlocks: %d blocks", cast(int)app.world.blocks.blocks.length);
}

@nogc pure bool hasBlocks(ref App app, TileType tt) nothrow {
  if(app.world.blocks is null) return false;
  return app.world.blocks.blocks.any!(b => b.type == tt);
}

/** Find the closest free block of given type, returns block ID or noBlock if none found */
uint findFreeBlock(ref App app, int[3] dwarfTile, TileType tt = TileType.None) {
  if(app.world.blocks is null) return noBlock;
  uint bestID = noBlock;
  float bestDist = float.max;
  foreach(ref b; app.world.blocks.blocks) {
    if(tt != TileType.None && b.type != tt) continue;
    if(b.tile == noTile) continue;  // carried
    bool reserved = false;
    if(app.world.dwarves !is null) foreach(ref d; app.world.dwarves) {
      foreach(j; d.jobStack) { if(j.blockID == b.id) { reserved = true; break; } }
      if(reserved) break;
    }
    if(reserved) continue;
    float dist = abs(b.tile[0] - dwarfTile[0]) + abs(b.tile[2] - dwarfTile[2]);
    if(dist < bestDist) { bestDist = dist; bestID = b.id; }
  }
  return bestID;
}

/** Create a drop instance */
Instance toDropInstance(ref App app, int[3] tile, TileType tt) {
  auto wp = app.world.tileToWorld(tile);
  wp[1] -= app.world.blockOffset;
  return Instance([cast(uint)tt, cast(uint)tt], translate(wp).multiply(scale([app.world.blockSize, app.world.blockSize, app.world.blockSize])));
}

/** Spawn a new block into the registry */
uint spawnBlock(ref App app, int[3] tile, TileType tt) {
  if(app.world.blocks is null) {
    app.world.blocks = new Blocks();
    app.objects ~= app.world.blocks;
  }
  auto b = Block(app.world.blocks.nextID++, tt, tile);
  app.world.blocks.blocks ~= b;
  app.world.blocks.instances ~= app.toDropInstance(tile, tt);
  app.world.blocks.buffers[INSTANCE] = false;
  return b.id;
}

/** Sync instances from blocks registry */
void syncBlockInstances(ref App app) {
  if(app.world.blocks is null) return;
  app.world.blocks.instances = [];
  foreach(ref b; app.world.blocks.blocks) {
    if(b.tile == noTile) {
      Instance inst;
      inst.matrix = inst.matrix.scale([0.0f, 0.0f, 0.0f]);
      app.world.blocks.instances ~= inst;
    } else { app.world.blocks.instances ~= app.toDropInstance(b.tile, b.type); }
  }
  app.world.blocks.buffers[INSTANCE] = false;
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
