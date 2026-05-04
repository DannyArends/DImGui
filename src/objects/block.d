/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import serialization : readWorldData, writeWorldData;
import inventory : deriveInventory;
import matrix : translateScale, translate, multiply, scale;
import vector : manhattan;
import world : noTile;

enum uint noBlock = uint.max;
enum int[3] builtTile = [int.max, 0, 0];

struct Block {
  uint id;              /// Unique block ID, forever
  TileType type;        /// Block type
  int[3] tile;          /// Current tile position
  float[2] fallState;   /// [y, v] fall physics, [0,0] if not falling

  @property @nogc bool isFalling() nothrow { return fallState[1] != 0.0f; }
  @property @nogc float y() nothrow { return fallState[0]; }
  @property @nogc float v() nothrow { return fallState[1]; }
  @property @nogc void y(float val) nothrow { fallState[0] = val; }
  @property @nogc void v(float val) nothrow { fallState[1] = val; }
}

class Blocks : Cube {
  Block[] blocks;           /// All blocks, forever
  uint nextID = 1;          /// Next block ID

  this() {
    super();
    initInstanced(() => "Blocks");
  }
}

/** Save blocks */
void saveBlocks(ref App app) {
  if(app.world.blocks is null) return;
  writeWorldData(app.world.blocksPath(), app.world.blocks.blocks, app.world.blocks.nextID);
}

/** Load blocks */
void loadBlocks(ref App app) {
  app.ensureBlocks();
  Block[] blocks;
  if(!readWorldData(app.world.blocksPath(), blocks, app.world.blocks.nextID)) return;
  app.world.blocks.blocks = blocks;
  foreach(ref b; app.world.blocks.blocks) {
    app.world.blocks.instances ~= app.world.toDropInstance(b.tile, b.type);
    if(b.isFalling) app.world.pendingUnsettle ~= b.tile;
  }
  app.world.blocks.markDirty();
  SDL_Log("loadBlocks: %d blocks", cast(int)app.world.blocks.blocks.length);
}

@nogc pure bool hasBlocks(ref App app) nothrow { return(app.world.blocks !is null && app.world.blocks.blocks.length > 0); }
@nogc pure bool hasBlocks(ref App app, TileType tt) nothrow { return(app.hasBlocks() && app.world.blocks.blocks.any!(b => b.type == tt)); }

/** Find the closest free block of given type, returns block ID or noBlock if none found */
uint findFreeBlock(ref App app, int[3] dwarfTile, TileType tt = TileType.None) {
  if(app.world.blocks is null) return noBlock;
  uint bestID = noBlock;
  float bestDist = float.max;
  foreach(ref b; app.world.blocks.blocks) {
    if(tt != TileType.None && b.type != tt) continue;
    if(b.tile == noTile || b.tile == builtTile) continue;
    bool reserved = false;
    if(app.world.dwarves !is null) foreach(ref d; app.world.dwarves) {
      foreach(j; d.jobStack) { if(j.blockIDs.canFind(b.id)) { reserved = true; break; } }
      if(reserved) break;
    }
    if(reserved) continue;
    if(!app.world.data.hasStandableNeighbour(b.tile)) continue;
    float dist = manhattan(b.tile, dwarfTile);
    if(dist < bestDist) { bestDist = dist; bestID = b.id; }
  }
  return bestID;
}

void ensureBlocks(ref App app) {
  if(app.world.blocks !is null) return;
  app.world.blocks = new Blocks();
  app.objects ~= app.world.blocks;
}

/** Create a drop instance */
DrawInstance toDropInstance(World world, int[3] tile, TileType tt) {
  return DrawInstance(tt, translateScale(world.tileToWorld(tile, -world.blockOffset), [world.blockSize, world.blockSize, world.blockSize]));
}

/** Spawn a new block into the registry */
uint spawnBlock(ref App app, int[3] tile, TileType tt) {
  app.ensureBlocks();
  auto b = Block(app.world.blocks.nextID++, tt, tile, [0.0f, 0.0f]);
  app.world.blocks.blocks ~= b;
  app.world.blocks.instances ~= app.world.toDropInstance(tile, tt);
  app.world.blocks.markDirty();
  return b.id;
}

/** Sync instances from blocks registry */
void syncBlockInstances(ref App app) {
  if(app.world.blocks is null) return;
  app.world.blocks.instances = [];
  int visible = 0, hidden = 0;
  foreach(ref b; app.world.blocks.blocks) {
    bool inactive = b.tile == noTile || b.tile == builtTile;
    app.world.blocks.instances ~= inactive ? DrawInstance(b.type, Matrix().scale([0.0f, 0.0f, 0.0f])) : app.world.toDropInstance(b.tile, b.type);
    if(inactive){ hidden++; }else{ visible++; }
  }
  //SDL_Log("syncBlockInstances: %d visible, %d hidden (total=%d)", visible, hidden, cast(int)app.world.blocks.blocks.length);
  app.world.blocks.markDirty();
}

@nogc pure bool isAbove(int[3] tile, int[3] other) nothrow { return tile[0] == other[0] && tile[2] == other[2] && tile[1] > other[1]; }

/** Mark blocks above a mined tile as falling */
void unsettleBlocks(const World world, ref Blocks blocks, int[3] minedTile) {
  if(blocks is null) return;
  foreach(ref b; blocks.blocks) {
    if(b.tile[0] != minedTile[0] || b.tile[2] != minedTile[2] || b.tile[1] < minedTile[1]) continue;
    if(!b.isFalling) b.fallState = [world.tileToWorld(b.tile, -world.blockOffset)[1], 0.001f];
  }
}

/** Update falling blocks */
void settleBlocks(const World world, ref Blocks blocks, float dt) {
  if(blocks is null) return;
  bool changed = false;
  foreach(i, ref b; blocks.blocks) {
    if(!b.isFalling) continue;
    //SDL_Log("settleBlocks: block %d falling y=%.2f", b.id, b.y);
    b.v = b.v + 0.125f * dt;
    b.y = b.y - b.v * dt;
    int landTileY = world.surfaceAt(b.tile[0], b.tile[1] - 1, b.tile[2]);
    float landY = world.tileToWorld([b.tile[0], landTileY + 1, b.tile[2]], -world.blockOffset)[1];
    if(b.y <= landY) {
      b.tile = [b.tile[0], landTileY + 1, b.tile[2]];
      b.fallState = [0.0f, 0.0f];  // settled
      blocks.instances[i].matrix[13] = world.tileToWorld(b.tile, -world.blockOffset)[1];
    } else { blocks.instances[i].matrix[13] = b.y; }
    changed = true;
  }
  if(changed) blocks.markDirty();
}
