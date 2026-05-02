/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : findFreeBlock;
import io : writeFile, readFile, fixPath, isfile;
import tileatlas : TileType, tileData;
import world : noTile, setTile;
import ghost : updateGhostTile, syncBuildGhosts;
import jobs : jobQueue, buildingJob;

struct Inventory {
  GhostCube ghost;
  alias ghost this;
  int[TileType] onFloor;
  int[TileType] carried;
  int[TileType] queued;
  bool isDragging = false;
  int[3][] dragPreview;

  int get(TileType tt, int def = 0) { return max(0, onFloor.get(tt, def) + carried.get(tt, def) - queued.get(tt, def)); }
  void clear() { onFloor.clear(); carried.clear(); queued.clear(); }
  void update(Blocks blocks, Dwarves dwarves, Job[] jobs) {
    clear();
    if(blocks !is null) {
      foreach(ref inst; blocks.instances) { auto tt = cast(TileType)inst.meshdef[0]; onFloor[tt] = onFloor.get(tt, 0) + 1; }
    }
    if(dwarves !is null) {
      foreach(ref d; dwarves) { foreach(tt; d.carrying) { carried[tt] = carried.get(tt, 0) + 1; } }
    }
    foreach(ref j; jobs) {
      if(j.name == "Building") queued[j.tileType] = queued.get(j.tileType, 0) + 1;
    }
  }
  string toString(TileType tt) const {
    return format("%s | Floor:%d Carried:%d Queued:%d", tileData[tt].name, onFloor.get(tt, 0), carried.get(tt, 0), queued.get(tt, 0));
  }
}

void deriveInventory(ref App app) {
  app.world.inventory.update(app.world.blocks, app.world.dwarves, jobQueue);
  auto prevLen = jobQueue.length;
  jobQueue = jobQueue.filter!(j => j.name != "Building" || app.world.inventory.get(j.tileType, 0) > 0).array;
  if(app.world.inventory.get(app.world.inventory.ghost.type, 0) <= 0) app.world.inventory.ghost.type = TileType.None;
  if(jobQueue.length != prevLen) app.syncBuildGhosts();
}

void placeTile(ref App app, int[3] wc) {
  if(wc == noTile) return;
  if(app.world.inventory.ghost.type == TileType.None) return;
  if(app.world.inventory.get(app.world.inventory.ghost.type, 0) <= 0) return;
  jobQueue ~= buildingJob(wc, app.world.inventory.ghost.type);
  app.syncBuildGhosts();
}

void computeDragPreview(ref App app, int[3] from, int[3] to) {
  int available = app.world.inventory.get(app.world.inventory.ghost.type, 0);
  int dx = abs(to[0] - from[0]);
  int dz = abs(to[2] - from[2]);
  app.world.inventory.dragPreview = [];
  if(dx >= dz) {  // snap to X axis
    int step = to[0] > from[0] ? 1 : -1;
    for(int x = from[0]; x != to[0] + step; x += step){
      if(app.world.getTile([x, from[1], from[2]]) != TileType.None) continue;
      app.world.inventory.dragPreview ~= [x, from[1], from[2]];
      if(app.world.inventory.dragPreview.length >= available) break;
    }
  } else {  // snap to Z axis
    int step = to[2] > from[2] ? 1 : -1;
    for(int z = from[2]; z != to[2] + step; z += step){
      if(app.world.getTile([from[0], from[1], z]) != TileType.None) continue;
      app.world.inventory.dragPreview ~= [from[0], from[1], z];
      if(app.world.inventory.dragPreview.length >= available) break;
    }
  }
}
