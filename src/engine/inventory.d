/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import io : writeFile, readFile, fixPath, isfile;
import tileatlas : TileType;
import world : setTile;
import ghost : updateGhostTile;
import jobs : BuildJob, buildQueue;

struct Inventory {
  int[TileType] items;
  TileType selectedTile = TileType.None;
  int[3] ghostTile = [int.min, 0, 0];
  Geometry ghostCube;
  alias items this;
}

void deriveInventory(ref App app) {
  app.inventory.items.clear();
  if(app.world.droppedBlocks is null) return;
  foreach(ref inst; app.world.droppedBlocks.instances) {
    auto tt = cast(TileType)inst.meshdef[0];
    app.inventory[tt] = app.inventory.get(tt, 0) + 1;
  }
  if(app.inventory.get(app.inventory.selectedTile, 0) <= 0) { app.inventory.selectedTile = TileType.None; }
}

void placeTile(ref App app, int[3] wc) {
  if(wc[0] == int.min) return;
  if(app.inventory.selectedTile == TileType.None) return;
  int reserved = cast(int)buildQueue.count!(j => j.tileType == app.inventory.selectedTile);
  if(app.inventory.get(app.inventory.selectedTile, 0) - reserved <= 0) return;
  buildQueue ~= BuildJob(wc, app.inventory.selectedTile);
}

