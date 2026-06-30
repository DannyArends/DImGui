/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import inventory : deriveInventory;
import icosahedron : refineIcosahedron;
import matrix : translateScale, scale;
import normals : computeTangents;
import physx : inColumn;
import serialization : readData, writeData;
import stockpile : slotsPerTile, subCellOffset, storedTileOf, emptySlot;
import resources : isFood;
import tile : isStandable, surfaceAt, hasStandableNeighbour, tileToWorld, worldToTile, tileAbove;
import vector : manhattan;

enum uint noBlock = uint.max;

struct Block {
  uint id = uint.max;               /// Stable block id (persisted, == its key in world.blocks)
  ResourceType type;                /// Block type
  int[3] tile;                      /// Current tile position
  Fall fall;                        /// PhysX
  size_t instanceIdx = size_t.max;  /// Instance IDX
  bool reserved = false;            /// Reserved for a job ?

  @property @nogc bool isFalling() const nothrow { return fall.isFalling; }
}

struct Drops {
  Block[uint] registry;
  alias registry this;
  bool dirty = false;
  uint nextID = 1;
  Geometry[string] meshes;
}


/** Save blocks */
void saveBlocks(ref World world) {
  if(world.drops.length == 0) return;
  foreach(id, ref b; world.drops) {
    if(b.fall.isFalling) { b.tile = b.fall.landingTile(world, b.tile); b.fall = Fall.init; }
  }
  Block[] flat = world.drops.values;
  writeData(world.blocksPath(), flat, world.drops.nextID);
}

/** Load blocks */
void loadBlocks(ref GameApp app) {
  app.ensureBlocks();
  Block[] flat;
  if(!readData(app.world.blocksPath(), flat, app.world.drops.nextID)) return;
  foreach(ref b; flat) {
    b.reserved = false;             // jobs aren't persisted; clear orphaned reservations
    app.world.drops[b.id] = b;
    if(b.id >= app.world.drops.nextID) app.world.drops.nextID = b.id + 1;
  }
  app.world.drops.dirty = true;
  SDL_Log("loadBlocks: %d blocks", cast(int)app.world.drops.length);
}

@nogc pure bool hasBlocks(const Block[uint] drops, ResourceType tt) nothrow { return drops.byValue.any!(b => b.type == tt); }

/** Returns the ResourceType of a block by ID, or ResourceType.None if not found */
ResourceType blockType(const Block[uint] drops, uint id) { auto b = id in drops; return b ? b.type : ResourceType.None; }

/** Tile a dwarf would path to in order to pick up block `b`, or noTile if unavailable */
int[3] pickupTileFor(const World world, uint id, const Block b, bool includeStored) {
  if(b.reserved || b.isFalling || b.tile == noTile || b.tile == builtTile) return noTile;
  if(b.tile == storedTile) {
    if(!includeStored) return noTile;
    auto pt = world.storedTileOf(id);
    return (pt != noTile && world.hasStandableNeighbour(pt.tileAbove)) ? pt : noTile;
  }
  return (world.isStandable(b.tile) || world.hasStandableNeighbour(b.tile)) ? b.tile : noTile;
}

/** Clear the reserved flag on a set of blocks (released on job failure/completion). */
void release(ref Block[uint] drops, uint[] ids) { foreach(id; ids){ if(auto b = id in drops){ b.reserved = false; } } }

/** Find the closest free block of given type, returns block ID or noBlock if none found */
private uint findFreeBlockWhere(alias accept)(const World world, const int[3] dwarfTile, bool includeStored) {
  uint bestID = noBlock; float bestDist = float.max;
  foreach(id, b; world.drops) {
    if(!accept(b)) continue;
    int[3] at = world.pickupTileFor(id, b, includeStored);
    if(at == noTile) continue;
    float dist = manhattan(at, dwarfTile);
    if(dist < bestDist) { bestDist = dist; bestID = id; }
  }
  return bestID;
}

uint findFreeBlock(const World world, const int[3] dwarfTile, ResourceType tt = ResourceType.None, bool includeStored = true) {
  return findFreeBlockWhere!(b => tt == ResourceType.None || b.type == tt)(world, dwarfTile, includeStored);
}

uint findFreeFood(const World world, const int[3] dwarfTile, bool includeStored = true) {
  return findFreeBlockWhere!(b => b.type.isFood)(world, dwarfTile, includeStored);
}

Geometry createDropMesh(string meshName) {
  switch(meshName) {
    case "Blocks":
      Geometry m = new Cube();
      m.initInstanced(() => meshName);
      return m;
    case "Berries":
      Geometry m = new Icosahedron();
      m.computeTangents();
      m.refineIcosahedron(3);
      m.initInstanced(() => meshName);
      return m;
    default: SDL_Log("ensureBlocks: unknown mesh type '%s'", toStringz(meshName)); return null;
  }
}

void ensureBlocks(ref GameApp app) {
  foreach(rt; EnumMembers!ResourceType) {
    auto meshName = resourceData(rt).meshName;
    if(meshName in app.world.drops.meshes) continue;
    auto m = createDropMesh(meshName);
    if(m is null) continue;
    app.world.drops.meshes[meshName] = m;
    app.objects ~= m;
  }
}

/** Spawn a new block into the registry */
uint spawnBlock(ref GameApp app, int[3] tile, ResourceType tt) {
  app.ensureBlocks();
  uint id = app.world.drops.nextID++;
  app.world.drops[id] = Block(id, tt, tile);
  app.world.drops.dirty = true;
  return id;
}

void emitBlock(ref Geometry mesh, uint id, ref Block b, float[3] pos, float[3] scale) {
  b.instanceIdx = mesh.instances.length;
  mesh.instances ~= DrawInstance([cast(uint)b.type, cast(uint)b.type], resourceData(b.type).color, translateScale(pos, scale));
}

/** Append instances for every stored block at its sub-cell within the owning pile */
void syncStockpileInstances(ref World world) {
  float bs = world.blockSize;
  foreach(ref sp; world.stockpiles) { foreach(i, blockID; sp.contents) {
    if(blockID == emptySlot) continue;
    auto b = blockID in world.drops;
    if(b is null) continue;
    auto ti = i / slotsPerTile;
    if(ti >= sp.tiles.length) break;
    float[3] base = world.tileToWorld(sp.tiles[ti].tileAbove, -world.blockOffset);
    float[3] off = world.subCellOffset(cast(uint)(i % slotsPerTile));
    emitBlock(world.drops.meshes[resourceData(b.type).meshName], blockID, *b, [base[0]+off[0], base[1]+off[1], base[2]+off[2]], [bs, bs, bs]);
  } }
}

/** Sync instances from blocks registry */
void syncBlockInstances(ref World world) {
  if(world.drops.meshes.length == 0) return;
  foreach(ref mesh; world.drops.meshes.values) { mesh.instances = []; }
  foreach(id, ref b; world.drops) {
    if(b.tile == storedTile) continue;
    auto meshName = resourceData(b.type).meshName;
    bool hidden = (b.tile == noTile || b.tile == builtTile || world.chunkCoord(b.tile) !in world.chunks);
    if(hidden) {
      emitBlock(world.drops.meshes[meshName], id, b, [0, 0, 0], [0, 0, 0]);
    } else {
      auto base = world.tileToWorld(b.tile, -world.blockOffset);
      float sz = resourceData(b.type).scale * world.blockSize;
      float bx = ((id * 1664525u  + 1013904223u) % 100u) / 100.0f - 0.5f;
      float bz = ((id * 22695477u + 1u) % 100u) / 100.0f - 0.5f;
      float by = b.fall.isFalling ? b.fall.y : base[1];
      emitBlock(world.drops.meshes[meshName], id, b, [base[0] + bx, by, base[2] + bz], [sz, sz, sz]);
    }
  }
  world.syncStockpileInstances();
  foreach(ref mesh; world.drops.meshes.values) { mesh.syncInstances(); }
}

/** Mark blocks above a mined tile as falling */
void unsettleBlocks(ref World world, ref Block[uint] drops, int[3] minedTile) {
  foreach(id, ref b; drops) {
    if(!inColumn(b.tile, minedTile)) continue;
    b.fall.start(world, b.tile, -world.blockOffset);
  }
}

/** Update falling blocks */
void settleBlocks(ref World world, float dt) {
  if(world.drops.length == 0) return;
  foreach(id, ref b; world.drops) {
    if(!b.fall.isFalling) continue;
    int[3] landed;
    if(b.fall.step(world, b.tile, dt, -world.blockOffset, landed)) b.tile = landed;
    world.drops.dirty = true;
  }
}
