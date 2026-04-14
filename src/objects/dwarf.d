/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry;

class Dwarf : Cylinder {
  string dwarfName;
  int[3] tilePos = [0, 0, 0];  /// Current tile position in world coordinates
}

bool isTileOccupied(ref App app, int[3] tile) {
  foreach(o; app.objects) {
    auto d = cast(Dwarf)o; if(d !is null && d.tilePos == tile) return true;
  }
  return false;
}

string randomDwarfName() {
  string[] prefixes = ["Urist", "Iden", "Meng", "Reg", "Doren", "Ast", "Nil", "Erib", "Thob", "Cog"];
  string[] suffixes = ["ral", "dor", "zan", "kel", "tok", "mis", "bur", "ith", "gar", "lon"];
  return prefixes[uniform(0, prefixes.length)] ~ suffixes[uniform(0, suffixes.length)];
}

int[3] findFreeSurfaceTile(ref App app, int startX = 0, int startZ = 0) {
  foreach(radius; 0..app.world.chunkSize) {
    for(int x = -radius; x <= radius; x++) {
      for(int z = -radius; z <= radius; z++) {
        int[3] tile = [startX + x, app.world.chunkHeight-1, startZ + z];
        while(tile[1] > 0) {
          auto coord = app.world.chunkCoord(tile);
          TileType tt = (coord in app.world.chunks) ? 
            app.world.chunks[coord].tileTypes[app.world.tileIndex(app.world.localCoord(tile))] :
            app.world.getTile(tile);
          if(tt != TileType.None) break;
          tile[1]--;
        }
        if(tile[1] > 0 && !app.isTileOccupied(tile)) return tile;
      }
    }
  }
  return [0, 0, 0];
}

Dwarf spawnDwarf(ref App app, string name) {
  auto tile = app.findFreeSurfaceTile();
  Dwarf dwarf = new Dwarf();
  dwarf.dwarfName = name;
  dwarf.tilePos = tile;
  auto wp = app.world.worldPos([tile[0], tile[1] + 1, tile[2]]);
  dwarf.position([wp[0], wp[1] + app.world.yOffset - 0.5, wp[2]]);
  dwarf.setColor([uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), 1.0f]);
  app.objects ~= dwarf;
  return dwarf;
}

