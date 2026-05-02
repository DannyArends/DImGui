/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import block : findFreeBlock;
import io : writeFile, readFile, fixPath, isfile;
import tileatlas : TileType;
import world : noTile, setTile;
import ghost : updateGhostTile;
import jobs : jobQueue, buildingJob;

struct Inventory {
  GhostCube ghost;
  int[TileType] items;
  alias items this;
}

void deriveInventory(ref App app) {
  app.world.inventory.items.clear();
  if(app.world.blocks !is null) {
    foreach(ref inst; app.world.blocks.instances) {
      auto tt = cast(TileType)inst.meshdef[0];
      app.world.inventory[tt] = app.world.inventory.get(tt, 0) + 1;
    }
  }
  if(app.world.dwarves !is null) {
    foreach(ref d; app.world.dwarves) { foreach(tt; d.carrying) { app.world.inventory[tt] = app.world.inventory.get(tt, 0) + 1; } }
  }
  if(app.world.inventory.get(app.world.inventory.ghost.type, 0) <= 0) app.world.inventory.ghost.type = TileType.None;
  jobQueue = jobQueue.filter!(j => j.name != "Building" || app.world.inventory.get(j.tileType, 0) > 0).array;
}

void placeTile(ref App app, int[3] wc) {
  if(wc == noTile) return;
  if(app.world.inventory.ghost.type == TileType.None) return;
  if(app.world.inventory.get(app.world.inventory.ghost.type, 0) <= 0) return;
  jobQueue ~= buildingJob(wc, app.world.inventory.ghost.type);
}
