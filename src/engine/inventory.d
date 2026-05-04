/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : builtTile;
import ghost : syncBuildGhosts;
import jobs : buildingJob, jobQueue;
import resources : resourceData, ResourceType;
import world : noTile;

struct Inventory {
  GhostCube ghost;
  alias ghost this;
  int[ResourceType] queued;
  bool isDragging = false;
  int[3][] dragPreview;

  int onFloor(ResourceType tt, Blocks blocks) const {
    if(blocks is null) return 0;
    return cast(int)blocks.blocks.count!(b => b.type == tt && b.tile != noTile && b.tile != builtTile);
  }
  int carried(ResourceType tt, Blocks blocks) const {
    if(blocks is null) return 0;
    return cast(int)blocks.blocks.count!(b => b.type == tt && b.tile == noTile);
  }
  int built(ResourceType tt, Blocks blocks) const {
    if(blocks is null) return 0;
    return cast(int)blocks.blocks.count!(b => b.type == tt && b.tile == builtTile);
  }
  int get(ResourceType tt, Blocks blocks) const { return max(0, onFloor(tt, blocks) + carried(tt, blocks) - queued.get(tt, 0)); }
  int total(ResourceType tt, Blocks blocks) const { return onFloor(tt, blocks) + carried(tt, blocks); }
  string toString(ResourceType tt, Blocks blocks) const {
    return format("%s | Available:%d (Floor:%d Carried:%d Queued:%d Built:%d)",
      resourceData(tt).name, get(tt, blocks), onFloor(tt, blocks), carried(tt, blocks), queued.get(tt, 0), built(tt, blocks));
  }
}

void deriveInventory(ref App app) {
  app.world.inventory.queued.clear();
  foreach(ref j; jobQueue) { if(j.name == "Building") app.world.inventory.queued[j.tileType] = app.world.inventory.queued.get(j.tileType, 0) + 1; }
  auto prevLen = jobQueue.length;
  jobQueue = jobQueue.filter!(j => j.name != "Building" || app.world.inventory.total(j.tileType, app.world.blocks) > 0).array;
  if(jobQueue.length != prevLen) {
    SDL_Log(toStringz(format("[Inventory] %d building jobs removed (inventory check)", cast(int)(prevLen - jobQueue.length))));
  }
  if(app.world.inventory.get(app.world.inventory.ghost.type, app.world.blocks) <= 0) app.world.inventory.ghost.type = ResourceType.None;
  if(jobQueue.length != prevLen) app.syncBuildGhosts();
}

void placeTile(ref App app, int[3] wc) {
  if(wc == noTile) return;
  if(app.world.inventory.ghost.type == ResourceType.None) return;
  if(app.world.inventory.get(app.world.inventory.ghost.type, app.world.blocks) <= 0) return;
  jobQueue ~= buildingJob(wc, app.world.inventory.ghost.type);
  app.syncBuildGhosts();
  app.deriveInventory();
}

void computeDragPreview(ref App app, int[3] from, int[3] to) {
  int available = app.world.inventory.get(app.world.inventory.ghost.type, app.world.blocks);
  int dx = abs(to[0] - from[0]);
  int dz = abs(to[2] - from[2]);
  app.world.inventory.dragPreview = [];
  if(dx >= dz) {  // snap to X axis
    int step = to[0] > from[0] ? 1 : -1;
    for(int x = from[0]; x != to[0] + step; x += step){
      if(app.world.getTile([x, from[1], from[2]]) != ResourceType.None) continue;
      app.world.inventory.dragPreview ~= [x, from[1], from[2]];
      if(app.world.inventory.dragPreview.length >= available) break;
    }
  } else {  // snap to Z axis
    int step = to[2] > from[2] ? 1 : -1;
    for(int z = from[2]; z != to[2] + step; z += step){
      if(app.world.getTile([from[0], from[1], z]) != ResourceType.None) continue;
      app.world.inventory.dragPreview ~= [from[0], from[1], z];
      if(app.world.inventory.dragPreview.length >= available) break;
    }
  }
}
