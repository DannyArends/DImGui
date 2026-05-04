/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import color : Colors, colorIndex;
import inventory : deriveInventory;
import matrix : translateScale, scale;
import serialization : readWorldData, writeWorldData;
import vector : manhattan;
import world : noTile;

enum uint noBlock = uint.max;
enum int[3] builtTile = [int.max, 0, 0];

struct Block {
  uint id;              /// Unique block ID, forever
  ResourceType type;    /// Block type
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

class Berries : Icosahedron {
  this() {
    super();
    initInstanced(() => "Berries");
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
  app.syncBlockInstances();
  foreach(ref b; app.world.blocks.blocks) {
    if(b.isFalling) app.world.pendingUnsettle ~= b.tile;
  }
  SDL_Log("loadBlocks: %d blocks", cast(int)app.world.blocks.blocks.length);
}

@nogc pure bool hasBlocks(ref App app) nothrow { return(app.world.blocks !is null && app.world.blocks.blocks.length > 0); }
@nogc pure bool hasBlocks(ref App app, ResourceType tt) nothrow { return(app.hasBlocks() && app.world.blocks.blocks.any!(b => b.type == tt)); }

/** Find the closest free block of given type, returns block ID or noBlock if none found */
uint findFreeBlock(ref App app, int[3] dwarfTile, ResourceType tt = ResourceType.None) {
  if(app.world.blocks is null) return noBlock;
  uint bestID = noBlock;
  float bestDist = float.max;
  foreach(ref b; app.world.blocks.blocks) {
    if(tt != ResourceType.None && b.type != tt) continue;
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
  app.world.berries = new Berries();
  app.objects ~= app.world.berries;
}

/** Create a drop instance */
DrawInstance toDropInstance(World world, int[3] tile, ResourceType tt) {
  return DrawInstance(tt, translateScale(world.tileToWorld(tile, -world.blockOffset), [world.blockSize, world.blockSize, world.blockSize]));
}

/** Spawn a new block into the registry */
uint spawnBlock(ref App app, int[3] tile, ResourceType tt) {
  app.ensureBlocks();
  auto b = Block(app.world.blocks.nextID++, tt, tile, [0.0f, 0.0f]);
  app.world.blocks.blocks ~= b;
  app.syncBlockInstances();
  return b.id;
}

@nogc pure float[3] wiggle(const Block b, float[3] base, uint s1, uint s2, uint s3, uint s4) nothrow {
  float bx = ((b.id * s1 + s2) % 100u) / 100.0f - 0.5f;
  float bz = ((b.id * s3 + s4) % 100u) / 100.0f - 0.5f;
  return [base[0]+bx, base[1], base[2]+bz];
}

DrawInstance toDropInstance(World world, ref Block b) {
  auto base = world.tileToWorld(b.tile, -world.blockOffset);
  if(b.type == ResourceType.Berry)
    return DrawInstance([0u, 0u, colorIndex(Colors.crimson), 0u],
      translateScale(b.wiggle(base, 1664525u, 1013904223u, 22695477u, 1u), [0.15f, 0.15f, 0.15f]));
  if(b.type == ResourceType.Wood)
    return DrawInstance(b.type,
      translateScale(b.wiggle(base, 1234567u, 891011u, 9876543u, 210987u), [world.blockSize, world.blockSize, world.blockSize]));
  return DrawInstance(b.type, translateScale(base, [world.blockSize, world.blockSize, world.blockSize]));
}

/** Sync instances from blocks registry */
void syncBlockInstances(ref App app) {
  if(app.world.blocks is null) return;
  app.world.blocks.instances = [];
  app.world.berries.instances = [];
  foreach(ref b; app.world.blocks.blocks) {
    bool hidden = b.tile == noTile || b.tile == builtTile;
    auto inst = hidden ? DrawInstance(b.type, Matrix().scale([0.0f, 0.0f, 0.0f])) : app.world.toDropInstance(b);
    if(b.type == ResourceType.Berry){
      app.world.berries.instances ~= inst;
    }else{ app.world.blocks.instances ~= inst; }
  }
  app.world.blocks.markDirty();
  app.world.berries.markDirty();
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
void settleBlocks(const World world, ref Blocks blocks, ref Berries berries, float dt) {
  if(blocks is null) return;
  bool changed = false;
  size_t bi = 0, ri = 0;
  foreach(ref b; blocks.blocks) {
    if(b.isFalling) {
      b.v = b.v + 0.125f * dt;
      b.y = b.y - b.v * dt;
      int landTileY = world.surfaceAt(b.tile[0], b.tile[1] - 1, b.tile[2]);
      float landY = world.tileToWorld([b.tile[0], landTileY + 1, b.tile[2]], -world.blockOffset)[1];
      if(b.y <= landY) {
        b.tile = [b.tile[0], landTileY + 1, b.tile[2]];
        b.fallState = [0.0f, 0.0f];
      }
      if(b.type == ResourceType.Berry) { berries.instances[ri].matrix[13] = b.isFalling ? b.y : world.tileToWorld(b.tile, -world.blockOffset)[1]; }
      else { blocks.instances[bi].matrix[13]  = b.isFalling ? b.y : world.tileToWorld(b.tile, -world.blockOffset)[1]; }
      changed = true;
    }
    if(b.type == ResourceType.Berry) ri++; else bi++;
  }
  if(changed) { blocks.markDirty(); berries.markDirty(); }
}
