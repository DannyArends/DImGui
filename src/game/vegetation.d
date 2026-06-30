/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import intersection : intersects;
import serialization : readData, writeData;
import tile : tileToWorld;

struct Vegetation {
  Feature[][int[3]][string] active;   alias active this;   // world.features[name][c] still works
  Feature[][int[3]][string] pending;
  bool[int[3]] modified;
  Geometry[string] meshes;
}

/** Create a tombstone entry for a cleared chunk */
T makeTombstone(T)(int[3] coord) if(is(typeof(T.init.rootTile) == int[3])) {
  T t;
  t.rootTile = [int.min, coord[0], coord[2]];
  return t;
}

/** Save vegetation objects to disk */
void saveVegetation(T)(ref GameApp app, ref T[][int[3]] objects, ref T[][int[3]] pending, const(char)* path) if(is(typeof(T.init.rootTile) == int[3])) {
  foreach(coord, items; pending) {
    if(coord !in objects) objects[coord] = items;
    else if(objects[coord].length == 0) objects[coord] = items;
  }
  pending.clear();
  T[] all;
  foreach(coord, items; objects) { all ~= items.length == 0 ? [makeTombstone!T(coord)] : items; }
  if(all.length == 0) return;
  writeData(path, all, cast(uint)all.length);
}

/** Load vegetation objects from disk into pending map */
void loadVegetation(T)(ref GameApp app, ref T[][int[3]] pending, const(char)* path) if(is(typeof(T.init.rootTile) == int[3])) {
  T[] items; uint i;
  if(!readData(path, items, i)) return;
  foreach(ref item; items) {
    if(item.rootTile[0] == int.min) { pending[[item.rootTile[1], 0, item.rootTile[2]]] = []; continue; }
    pending[app.world.chunkCoord(item.rootTile)] ~= item;
  }
}

/** Get the best vegetaion hit */
bool getBestVegetation(T, alias matchGeometry)(ref GameApp app, float[3][2] ray, Intersection[] hits, T[][int[3]] objects, out int[3] rootTile)
  if(is(typeof(T.init.rootTile) == int[3])) {
  Intersection best;
  foreach(ref hit; hits) {
    if(!matchGeometry(app.objects[hit.idx[0]].geometry())) continue;
    foreach(ref chunk; objects.values) foreach(ref t; chunk) {
      if(!t.matchIndex(hit.idx[1])) continue;
      auto wp = app.world.tileToWorld(t.rootTile);
      float[3] bmin = [wp[0] - 1.0f, wp[1], wp[2] - 1.0f];
      float[3] bmax = [wp[0] + 1.0f, wp[1] + t.bboxHeight + 1.5f, wp[2] + 1.0f];
      auto i = ray.intersects(bmin, bmax, hit.idx[0], hit.idx[1]);
      if(i.intersects && (!best.intersects || i.tmin < best.tmin)) { best = i; rootTile = t.rootTile; }
    }
  }
  return best.intersects;
}
