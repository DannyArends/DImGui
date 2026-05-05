/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import color : Colors, colorIndex;
import inventory : deriveInventory;
import icosahedron : refineIcosahedron;
import matrix : translateScale, scale;
import resources : resourceData;
import serialization : readWorldData, writeWorldData;
import normals : computeTangents;
import vector : manhattan;
import world : noTile;

enum uint noBlock = uint.max;
enum int[3] builtTile = [int.max, 0, 0];

struct Block {
  uint id;                          /// Unique block ID, forever
  ResourceType type;                /// Block type
  int[3] tile;                      /// Current tile position
  float[2] fallState;               /// [y, v] fall physics, [0,0] if not falling
  size_t instanceIdx = size_t.max;  /// Instance IDX
  bool reserved = false;            /// Reserved for a job ?
  bool reachable = false;           /// Has a standable neighbour ?

  @property @nogc bool isFalling() nothrow { return fallState[1] != 0.0f; }
  @property @nogc float y() nothrow { return fallState[0]; }
  @property @nogc float v() nothrow { return fallState[1]; }
  @property @nogc void y(float val) nothrow { fallState[0] = val; }
  @property @nogc void v(float val) nothrow { fallState[1] = val; }
}

/** Save blocks */
void saveBlocks(ref App app) {
  if(app.world.blocks.length == 0) return;
  writeWorldData(app.world.blocksPath(), app.world.blocks, app.world.blockNextID);
}

/** Load blocks */
void loadBlocks(ref App app) {
  app.ensureBlocks();
  Block[] blocks;
  if(!readWorldData(app.world.blocksPath(), blocks, app.world.blockNextID)) return;
  app.world.blocks = blocks;
  app.syncBlockInstances();
  foreach(ref b; app.world.blocks) { if(b.isFalling) app.world.pendingUnsettle ~= b.tile; }
  SDL_Log("loadBlocks: %d blocks", cast(int)app.world.blocks.length);
}

@nogc pure bool hasBlocks(ref App app) nothrow { return app.world.blocks.length > 0; }
@nogc pure bool hasBlocks(ref App app, ResourceType tt) nothrow { return app.world.blocks.any!(b => b.type == tt); }

/** Find the closest free block of given type, returns block ID or noBlock if none found */
uint findFreeBlock(ref App app, int[3] dwarfTile, ResourceType tt = ResourceType.None) {
  if(app.world.blocks.length == 0) return noBlock;
  uint bestID = noBlock;
  float bestDist = float.max;
  foreach(ref b; app.world.blocks) {
    if(!b.reachable || b.reserved || b.tile == noTile || b.tile == builtTile) continue;
    if(tt != ResourceType.None && b.type != tt) continue;

    float dist = manhattan(b.tile, dwarfTile);
    if(dist < bestDist) { bestDist = dist; bestID = b.id; }
  }
  return bestID;
}

void ensureBlocks(ref App app) {
  foreach(rt; EnumMembers!ResourceType) {
    auto meshName = resourceData(rt).meshName;
    if(meshName in app.world.dropMeshes) continue;
    if(meshName == "Blocks") {
      Geometry m = new Cube();
      m.initInstanced(() => meshName);
      app.world.dropMeshes[meshName] = m;
      app.objects ~= m;
    }
    if(meshName == "Berries") {
      Geometry m = new Icosahedron();
      m.computeTangents();
      m.refineIcosahedron(3);
      m.initInstanced(() => meshName);
      app.world.dropMeshes[meshName] = m;
      app.objects ~= m;
    }
  }
}

/** Spawn a new block into the registry */
uint spawnBlock(ref App app, int[3] tile, ResourceType tt) {
  app.ensureBlocks();
  auto b = Block(app.world.blockNextID++, tt, tile, [0.0f, 0.0f]);
  app.world.blocks ~= b;
  app.syncBlockInstances();
  return b.id;
}

DrawInstance toDropInstance(World world, ref Block b) {
  auto rd = resourceData(b.type);
  auto base = world.tileToWorld(b.tile, -world.blockOffset);
  float sz = rd.dropScale * world.blockSize;
  float bx = ((b.id * 1664525u  + 1013904223u) % 100u) / 100.0f - 0.5f;
  float bz = ((b.id * 22695477u + 1u)          % 100u) / 100.0f - 0.5f;
  float[3] pos = [base[0] + bx, base[1], base[2] + bz];
  return DrawInstance([cast(uint)b.type, cast(uint)b.type, colorIndex(resourceData(b.type).color), 0u], translateScale(pos, [sz, sz, sz]));
}

/** Sync instances from blocks registry */
void syncBlockInstances(ref App app) {
  if(app.world.dropMeshes.length == 0) return;
  foreach(ref mesh; app.world.dropMeshes.values) mesh.instances = [];
  foreach(ref b; app.world.blocks) {
    if(b.tile != noTile && b.tile != builtTile){ b.reachable = app.world.data.hasStandableNeighbour(b.tile); }
    auto meshName = resourceData(b.type).meshName;
    bool hidden = b.tile == noTile || b.tile == builtTile;
    b.instanceIdx = app.world.dropMeshes[meshName].instances.length;
    app.world.dropMeshes[meshName].instances ~= hidden
      ? DrawInstance(b.type, Matrix().scale([0.0f, 0.0f, 0.0f]))
      : app.world.toDropInstance(b);
  }
  foreach(ref mesh; app.world.dropMeshes.values) mesh.markDirty();
}

@nogc pure bool isAbove(int[3] tile, int[3] other) nothrow { return tile[0] == other[0] && tile[2] == other[2] && tile[1] > other[1]; }

/** Mark blocks above a mined tile as falling */
void unsettleBlocks(const World world, ref Block[] blocks, int[3] minedTile) {
  foreach(ref b; blocks) {
    if(b.tile[0] != minedTile[0] || b.tile[2] != minedTile[2] || b.tile[1] < minedTile[1]) continue;
    if(!b.isFalling) b.fallState = [world.tileToWorld(b.tile, -world.blockOffset)[1], 0.001f];
  }
}

/** Update falling blocks */
void settleBlocks(ref World world, float dt) {
  if(world.blocks.length == 0) return;
  bool changed = false;
  foreach(ref b; world.blocks) {
    if(!b.isFalling) continue;
    b.v = b.v + 0.125f * dt;
    b.y = b.y - b.v * dt;
    int landTileY = world.surfaceAt(b.tile[0], b.tile[1] - 1, b.tile[2]);
    float landY = world.tileToWorld([b.tile[0], landTileY + 1, b.tile[2]], -world.blockOffset)[1];
    if(b.y <= landY) { b.tile = [b.tile[0], landTileY + 1, b.tile[2]]; b.fallState = [0.0f, 0.0f]; }
    float posY = b.isFalling ? b.y : world.tileToWorld(b.tile, -world.blockOffset)[1];
    world.dropMeshes[resourceData(b.type).meshName].instances[b.instanceIdx].matrix[13] = posY;
    changed = true;
  }
  if(changed) foreach(ref mesh; world.dropMeshes.values) mesh.markDirty();
}
