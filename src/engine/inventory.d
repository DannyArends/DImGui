/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import io : writeFile, readFile, fixPath, isfile;
import tileatlas : TileType;
import world : setTile;

struct Inventory {
  int[TileType] inventory;
  TileType selectedTile = TileType.None;
  int[3] ghostTile = [int.min, 0, 0];
  Geometry ghostCube;
  alias inventory this;
}

const(char)* inventoryPath(int[2] seed) { return(fixPath(toStringz(format("data/world/%d_%d/inventory.bin", seed[0], seed[1])))); }

void saveInventory(ref App app) {
  int[] data;
  foreach(tileType, count; app.inventory) {
    data ~= cast(int)tileType;
    data ~= count;
  }
  if(data.length > 0) writeFile(inventoryPath(app.world.seed), cast(char[])data, false);
}

void loadInventory(ref App app) {
  auto path = inventoryPath(app.world.seed);
  if(!path.isfile()) return;
  auto raw = cast(int[])readFile(path);
  for(int i = 0; i + 1 < raw.length; i += 2) {
    app.inventory[cast(TileType)raw[i]] = raw[i+1];
  }
}

void placeTile(ref App app, int[3] wc) {
  if(app.inventory.selectedTile != TileType.None && app.inventory.get(app.inventory.selectedTile, 0) > 0) {
    app.setTile(wc, app.inventory.selectedTile);
    app.inventory[app.inventory.selectedTile]--;
    if(app.inventory[app.inventory.selectedTile] <= 0) {
      app.inventory.inventory.remove(app.inventory.selectedTile);
      app.inventory.selectedTile = TileType.None;
    }
    app.saveInventory();
  }
}

