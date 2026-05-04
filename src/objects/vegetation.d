/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import serialization : readWorldData, writeWorldData;

/// Create a tombstone entry for a cleared chunk
T makeTombstone(T)(int[3] coord) if(is(typeof(T.init.rootTile) == int[3])) {
  T t;
  t.rootTile = [int.min, coord[0], coord[2]];
  return t;
}

/// Save vegetation objects to disk
void saveVegetation(T)(ref App app, ref T[][int[3]] objects, ref T[][int[3]] pending, const(char)* path)
  if(is(typeof(T.init.rootTile) == int[3])) {
  foreach(coord, items; pending) {
    if(coord !in objects) objects[coord] = items;
    else if(objects[coord].length == 0) objects[coord] = items;
  }
  pending.clear();
  T[] all;
  foreach(coord, items; objects) {
    all ~= items.length == 0 ? [makeTombstone!T(coord)] : items;
  }
  if(all.length == 0) return;
  writeWorldData(path, all, cast(uint)all.length);
}

/// Load vegetation objects from disk into pending map
void loadVegetation(T)(ref App app, ref T[][int[3]] pending, const(char)* path)
  if(is(typeof(T.init.rootTile) == int[3])) {
  T[] items; uint i;
  if(!readWorldData(path, items, i)) return;
  foreach(ref item; items) {
    if(item.rootTile[0] == int.min) { pending[[item.rootTile[1], 0, item.rootTile[2]]] = []; continue; }
    pending[app.world.chunkCoord(item.rootTile)] ~= item;
  }
}

/// Remove vegetation for a chunk and rebuild instances
void removeVegetation(T, alias rebuildFn)(ref App app, ref T[][int[3]] objects, int[3] coord)
  if(is(typeof(T.init.rootTile) == int[3])) {
  if(coord !in objects) return;
  objects.remove(coord);
  rebuildFn(app);
}