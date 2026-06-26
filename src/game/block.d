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

  @property @nogc bool isFalling() nothrow { return fall.isFalling; }
}

/** Save blocks */
void saveBlocks(ref GameApp app) {
  if(app.world.blocks.length == 0) return;
  foreach(id, ref b; app.world.blocks) {
    if(b.fall.isFalling) { b.tile = b.fall.landingTile(app.world, b.tile); b.fall = Fall.init; }
  }
  Block[] flat = app.world.blocks.values;
  writeData(app.world.blocksPath(), flat, app.world.blockNextID);
}

/** Load blocks */
void loadBlocks(ref GameApp app) {
  app.ensureBlocks();
  Block[] flat;
  if(!readData(app.world.blocksPath(), flat, app.world.blockNextID)) return;
  foreach(ref b; flat) {
    b.reserved = false;             // jobs aren't persisted; clear orphaned reservations
    app.world.blocks[b.id] = b;
    if(b.id >= app.world.blockNextID) app.world.blockNextID = b.id + 1;
  }
  app.world.blocksDirty = true;
  SDL_Log("loadBlocks: %d blocks", cast(int)app.world.blocks.length);
}

@nogc pure bool hasBlocks(ref GameApp app) nothrow { return app.world.blocks.length > 0; }
@nogc pure bool hasBlocks(ref GameApp app, ResourceType tt) nothrow { return app.world.blocks.byValue.any!(b => b.type == tt); }

/** Tile a dwarf would path to in order to pick up block `b`, or noTile if unavailable */
int[3] pickupTileFor(ref GameApp app, uint id, ref Block b, bool includeStored) {
  if(b.reserved || b.isFalling || b.tile == noTile || b.tile == builtTile) return noTile;
  if(b.tile == storedTile) {
    if(!includeStored) return noTile;
    auto pt = app.storedTileOf(id);
    return (pt != noTile && app.world.hasStandableNeighbour(pt.tileAbove)) ? pt : noTile;
  }
  return app.world.hasStandableNeighbour(b.tile) ? b.tile : noTile;
}

/** Clear the reserved flag on a set of blocks (released on job failure/completion). */
void releaseBlocks(ref GameApp app, uint[] ids) { foreach(id; ids){ if(auto b = id in app.world.blocks){ b.reserved = false; } } }

/** Find the closest free block of given type, returns block ID or noBlock if none found */
uint findFreeBlock(ref GameApp app, int[3] dwarfTile, ResourceType tt = ResourceType.None, bool includeStored = true) {
  uint bestID = noBlock;
  float bestDist = float.max;
  foreach(id, ref b; app.world.blocks) {
    if(tt != ResourceType.None && b.type != tt) continue;
    int[3] at = app.pickupTileFor(id, b, includeStored);
    if(at == noTile) continue;
    float dist = manhattan(at, dwarfTile);
    if(dist < bestDist) { bestDist = dist; bestID = id; }
  }
  return bestID;
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
    if(meshName in app.world.dropMeshes) continue;
    auto m = createDropMesh(meshName);
    if(m is null) continue;
    app.world.dropMeshes[meshName] = m;
    app.objects ~= m;
  }
}

/** Spawn a new block into the registry */
uint spawnBlock(ref GameApp app, int[3] tile, ResourceType tt) {
  app.ensureBlocks();
  uint id = app.world.blockNextID++;
  app.world.blocks[id] = Block(id, tt, tile);
  app.world.blocksDirty = true;
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
    auto b = blockID in world.blocks;
    if(b is null) continue;
    auto ti = i / slotsPerTile;
    if(ti >= sp.tiles.length) break;
    float[3] base = world.tileToWorld(sp.tiles[ti].tileAbove, -world.blockOffset);
    float[3] off = world.subCellOffset(cast(uint)(i % slotsPerTile));
    emitBlock(world.dropMeshes[resourceData(b.type).meshName], blockID, *b, [base[0]+off[0], base[1]+off[1], base[2]+off[2]], [bs, bs, bs]);
  } }
}

/** Sync instances from blocks registry */
void syncBlockInstances(ref GameApp app) {
  if(app.world.dropMeshes.length == 0) return;
  foreach(ref mesh; app.world.dropMeshes.values) { mesh.instances = []; }
  foreach(id, ref b; app.world.blocks) {
    if(b.tile == storedTile) continue;
    auto meshName = resourceData(b.type).meshName;
    bool hidden = (b.tile == noTile || b.tile == builtTile || app.world.chunkCoord(b.tile) !in app.world.chunks);
    if(hidden) {
      emitBlock(app.world.dropMeshes[meshName], id, b, [0, 0, 0], [0, 0, 0]);
    } else {
      auto base = app.world.tileToWorld(b.tile, -app.world.blockOffset);
      float sz = resourceData(b.type).dropScale * app.world.blockSize;
      float bx = ((id * 1664525u  + 1013904223u) % 100u) / 100.0f - 0.5f;
      float bz = ((id * 22695477u + 1u) % 100u) / 100.0f - 0.5f;
      float by = b.fall.isFalling ? b.fall.y : base[1];
      emitBlock(app.world.dropMeshes[meshName], id, b, [base[0] + bx, by, base[2] + bz], [sz, sz, sz]);
    }
  }
  app.world.syncStockpileInstances();
  foreach(ref mesh; app.world.dropMeshes.values) { mesh.instances.invalidate(); }
}

/** Mark blocks above a mined tile as falling */
void unsettleBlocks(ref World world, ref Block[uint] blocks, int[3] minedTile) {
  foreach(id, ref b; blocks) {
    if(!inColumn(b.tile, minedTile)) continue;
    b.fall.start(world, b.tile, -world.blockOffset);
  }
}

/** Update falling blocks */
void settleBlocks(ref World world, float dt) {
  if(world.blocks.length == 0) return;
  foreach(id, ref b; world.blocks) {
    if(!b.fall.isFalling) continue;
    int[3] landed;
    if(b.fall.step(world, b.tile, dt, -world.blockOffset, landed)) b.tile = landed;
    world.blocksDirty = true;
  }
}
