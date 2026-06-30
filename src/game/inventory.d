/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import ghost : syncBuildGhosts;
import jobs : buildingJob, jobQueue;
import tile : getTileAt;

struct Inventory {
  GhostCube ghost;
  alias ghost this;
  int[ResourceType] queued;

  int onFloor(ResourceType tt, ref GameApp app) const {
    return cast(int)app.world.drops.byValue.count!(b => b.type == tt && b.tile != noTile && b.tile != builtTile);
  }
  int carried(ResourceType tt, ref GameApp app) const {
    return cast(int)app.world.drops.byValue.count!(b => b.type == tt && b.tile == noTile);
  }
  int built(ResourceType tt, ref GameApp app) const {
    return cast(int)app.world.drops.byValue.count!(b => b.type == tt && b.tile == builtTile);
  }
  int get(ResourceType tt, ref GameApp app) const { return max(0, onFloor(tt, app) + carried(tt, app) - queued.get(tt, 0)); }
  int total(ResourceType tt, ref GameApp app) const { return onFloor(tt, app) + carried(tt, app); }
  string toString(ResourceType tt, ref GameApp app) const {
    return format("%s | Available:%d (Floor:%d Carried:%d Queued:%d Built:%d)",
      resourceData(tt).name, get(tt, app), onFloor(tt, app), carried(tt, app), queued.get(tt, 0), built(tt, app));
  }
}

void deriveInventory(ref GameApp app) {
  app.world.inventory.queued.clear();
  foreach(ref j; jobQueue.filter!(j => j.name == "Building")) {
    app.world.inventory.queued[j.tileType] = app.world.inventory.queued.get(j.tileType, 0) + 1;
  }
  if(app.world.dwarves !is null){
    foreach(ref d; app.world.dwarves.dwarves){ foreach(ref j; d.jobStack){
        if(j.name == "Building"){ app.world.inventory.queued[j.tileType] = app.world.inventory.queued.get(j.tileType, 0) + 1; }
    } }
  }
  jobQueue = jobQueue.filter!(j => j.name != "Building" || app.world.inventory.total(j.tileType, app) > 0).array;
  if(app.world.inventory.get(app.world.inventory.type, app) <= 0) { app.world.inventory.type = ResourceType.None; }
}

void placeTile(ref GameApp app, int[3] wc) {
  if(wc == noTile) return;
  if(app.world.inventory.type == ResourceType.None) return;
  if(app.world.inventory.get(app.world.inventory.type, app) <= 0) return;
  jobQueue ~= buildingJob(wc, app.world.inventory.type);
  app.syncBuildGhosts();
  app.deriveInventory();
}

void computeDragPreview(ref GameApp app, int[3] from, int[3] to) {
  int axis = abs(to[0] - from[0]) >= abs(to[2] - from[2]) ? 0 : 2;   // step along X or Z
  int step = to[axis] > from[axis] ? 1 : -1;
  app.world.inventory.paint.preview = [];
  for(int v = from[axis]; v != to[axis] + step; v += step) {
    int[3] cell = from;
    cell[axis] = v;
    if(app.world.getTileAt(cell) != ResourceType.None) continue;   // target cell must be empty
    app.world.inventory.paint.preview ~= cell;
  }
}

