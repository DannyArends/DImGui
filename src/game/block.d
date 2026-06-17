/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import inventory : deriveInventory;
import icosahedron : refineIcosahedron;
import matrix : translateScale, scale;
import normals : computeTangents;
import serialization : readData, writeData;
import stockpile : slotsPerTile, subCellOffset;
import tile : isStandable, surfaceAt, hasStandableNeighbour, tileToWorld, worldToTile;
import vector : manhattan;

enum uint noBlock = uint.max;

struct Block {
  uint id = uint.max;               /// Stable block id (persisted, == its key in world.blocks)
  ResourceType type;                /// Block type
  int[3] tile;                      /// Current tile position
  float[2] fallState;               /// [y, v] fall physics, [0,0] if not falling
  size_t instanceIdx = size_t.max;  /// Instance IDX
  bool reserved = false;            /// Reserved for a job ?

  @property @nogc bool isFalling() nothrow { return fallState[1] != 0.0f; }
  @property @nogc float y() nothrow { return fallState[0]; }
  @property @nogc float v() nothrow { return fallState[1]; }
  @property @nogc void y(float val) nothrow { fallState[0] = val; }
  @property @nogc void v(float val) nothrow { fallState[1] = val; }
}

/** Save blocks */
void saveBlocks(ref GameApp app) {
  if(app.world.blocks.length == 0) return;
  Block[] flat = app.world.blocks.values;
  writeData(app.world.blocksPath(), flat, app.world.blockNextID);
}

/** Load blocks */
void loadBlocks(ref GameApp app) {
  app.ensureBlocks();
  Block[] flat;
  if(!readData(app.world.blocksPath(), flat, app.world.blockNextID)) return;
  foreach(ref b; flat) {
    app.world.blocks[b.id] = b;
    if(b.id >= app.world.blockNextID) app.world.blockNextID = b.id + 1;
  }
  app.syncBlockInstances();
  foreach(id, ref b; app.world.blocks) { if(b.isFalling) app.world.pendingUnsettle ~= b.tile; }
  SDL_Log("loadBlocks: %d blocks", cast(int)app.world.blocks.length);
}

@nogc pure bool hasBlocks(ref GameApp app) nothrow { return app.world.blocks.length > 0; }
@nogc pure bool hasBlocks(ref GameApp app, ResourceType tt) nothrow { return app.world.blocks.byValue.any!(b => b.type == tt); }

/** Find the closest free block of given type, returns block ID or noBlock if none found */
uint findFreeBlock(ref GameApp app, int[3] dwarfTile, ResourceType tt = ResourceType.None) {
  uint bestID = noBlock;
  float bestDist = float.max;
  foreach(id, ref b; app.world.blocks) {
    if(b.reserved || b.tile == noTile || b.tile == builtTile) continue;
    if(tt != ResourceType.None && b.type != tt) continue;
    if(!app.world.isStandable(b.tile)) continue;
    float dist = manhattan(b.tile, dwarfTile);
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
  app.world.blocks[id] = Block(id, tt, tile, [app.world.tileToWorld(tile, -app.world.blockOffset)[1], 0.001f]);
  app.syncBlockInstances();
  return id;
}

DrawInstance toDropInstance(World world, uint id, ref Block b) {
  auto rd = resourceData(b.type);
  auto base = world.tileToWorld(b.tile, -world.blockOffset);
  float sz = rd.dropScale * world.blockSize;
  float bx = ((id * 1664525u  + 1013904223u) % 100u) / 100.0f - 0.5f;
  float bz = ((id * 22695477u + 1u) % 100u) / 100.0f - 0.5f;
  float[3] pos = [base[0] + bx, base[1], base[2] + bz];
  return DrawInstance([cast(uint)b.type, cast(uint)b.type], resourceData(b.type).color, translateScale(pos, [sz, sz, sz]));
}

/** Append instances for every stored block at its sub-cell within the owning pile */
void syncStockpileInstances(ref GameApp app) {
  float bs = app.world.blockSize;
  foreach(ref sp; app.world.stockpiles) {
    foreach(i, blockID; sp.contents) {
      auto b = blockID in app.world.blocks;
      if(b is null) continue;
      auto meshName = resourceData(b.type).meshName;
      int[3] tile   = sp.tiles[i / slotsPerTile];
      float[3] base = app.world.tileToWorld(tile, -app.world.blockOffset);
      float[3] off  = app.subCellOffset(cast(uint)(i % slotsPerTile));
      float[3] pos  = [base[0] + off[0], base[1] + off[1], base[2] + off[2]];
      b.instanceIdx = app.world.dropMeshes[meshName].instances.length;
      app.world.dropMeshes[meshName].instances ~= DrawInstance(
        [cast(uint)b.type, cast(uint)b.type], resourceData(b.type).color,
        translateScale(pos, [bs, bs, bs]));
    }
  }
}

/** Sync instances from blocks registry */
void syncBlockInstances(ref GameApp app) {
  if(app.world.dropMeshes.length == 0) return;
  foreach(ref mesh; app.world.dropMeshes.values) mesh.instances = [];
  foreach(id, ref b; app.world.blocks) {
    auto meshName = resourceData(b.type).meshName;
    bool hidden = b.tile == noTile || b.tile == builtTile || app.world.chunkCoord(b.tile) !in app.world.chunks;
    b.instanceIdx = app.world.dropMeshes[meshName].instances.length;
    app.world.dropMeshes[meshName].instances ~= hidden
      ? DrawInstance([cast(uint)b.type, cast(uint)b.type], Matrix().scale([0.0f, 0.0f, 0.0f]))
      : app.world.toDropInstance(id, b);
  }
  app.syncStockpileInstances();
  foreach(ref mesh; app.world.dropMeshes.values) mesh.instances.buffered = false;
}

/** Mark blocks above a mined tile as falling */
void unsettleBlocks(const World world, ref Block[uint] blocks, int[3] minedTile) {
  foreach(id, ref b; blocks) {
    if(b.tile[0] != minedTile[0] || b.tile[2] != minedTile[2] || b.tile[1] < minedTile[1]) continue;
    if(!b.isFalling) b.fallState = [world.tileToWorld(b.tile, -world.blockOffset)[1], 0.001f];
  }
}

/** Update falling blocks */
void settleBlocks(ref World world, float dt) {
  if(world.blocks.length == 0) return;
  bool changed = false;
  foreach(id, ref b; world.blocks) {
    if(!b.isFalling) continue;
    b.v = b.v + (2.5f * dt);
    b.y = b.y - (b.v * dt);
    int landTileY = world.surfaceAt(b.tile[0], b.tile[1] - 1, b.tile[2]);
    float landY = world.tileToWorld([b.tile[0], landTileY + 1, b.tile[2]], -world.blockOffset)[1];
    if(b.y <= landY) { b.tile = [b.tile[0], landTileY + 1, b.tile[2]]; b.fallState = [0.0f, 0.0f]; }
    float posY = b.isFalling ? b.y : world.tileToWorld(b.tile, -world.blockOffset)[1];
    world.dropMeshes[resourceData(b.type).meshName].instances[b.instanceIdx].matrix[13] = posY;
    changed = true;
  }
  if(changed) foreach(ref mesh; world.dropMeshes.values) mesh.instances.buffered = false;
}
