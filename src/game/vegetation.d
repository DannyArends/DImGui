/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import lattice : tileToWorld, chunkCoord;

alias Vegetation = Features;

/** Create a tombstone entry for a cleared chunk */
T makeTombstone(T)(int[3] coord) if(is(typeof(T.init.rootTile) == int[3])) {
  T t;
  t.rootTile = [int.min, coord[0], coord[2]];
  return(t);
}

/** Save vegetation objects to disk */
T[] saveVegetation(T)(ref GameApp app, ref T[][int[3]] objects, ref T[][int[3]] pending) if(is(typeof(T.init.rootTile) == int[3])) {
  foreach(coord, items; pending) {
    if(coord !in objects) {
      objects[coord] = items;
    }else if(objects[coord].length == 0) { objects[coord] = items; }
  }
  pending.clear();
  T[] all;
  foreach(coord, items; objects) { all ~= items.length == 0 ? [makeTombstone!T(coord)] : items; }
  return(all);
}

/** Load vegetation objects from disk into pending map */
void loadVegetation(T)(ref GameApp app, ref T[][int[3]] pending, T[] items) if(is(typeof(T.init.rootTile) == int[3])) {
  foreach(ref item; items) {
    if(item.rootTile[0] == int.min) { pending[[item.rootTile[1], 0, item.rootTile[2]]] = []; continue; }
    pending[app.world.chunkCoord(item.rootTile)] ~= item;
  }
}

/** Get a vegetation section to persit to disk */
Persist vegetationSection(ref GameApp app, string name) {
  return Persist(
    () => [Section("veg:" ~ name, cast(ubyte[])app.saveVegetation!Feature(app.world.features[name], app.world.features.pending[name]))],
    (const ubyte[][string] b) {
      if(auto p = ("veg:" ~ name) in b) {
        app.loadVegetation!Feature(app.world.features.pending[name], cast(Feature[])(*p));
        foreach(coord, items; app.world.features.pending[name]){ if(items.length > 0){ app.world.features.modified[coord] = true; } }
      }
    });
}
