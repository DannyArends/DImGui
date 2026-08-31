/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : itemOf;
import feature : rebuildAllFeatures;
import jobs : consumeCarried;
import lattice : chunkCoord;
import resources : matchDemand;

alias Workshops = Features;

/** The [WORKSHOP] raw of this name. */
ref immutable(RawT) workshopFor(string name) {
  foreach(ref w; workshopTable) { if(w.name == name) { return(w); } }
  assert(0, "no [WORKSHOP] named " ~ name);
}

/** Root a workshop feature at `tile`: inject it, mark the chunk edited, rebuild instances. */
void placeWorkshop(ref GameApp app, string name, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  uint hash = cast(uint)(tile[0] * 73856093) ^ cast(uint)(tile[2] * 19349663);
  app.world.features[name][coord] ~= Feature(tile, 1, hash);
  app.world.features.modified[coord] = true;
  app.rebuildAllFeatures();
}

/** Consume the dwarf's carried buildCost, then root the workshop at the job's target tile. */
void finishWorkshop(ref GameApp app, ref Dwarf d) {
  foreach(ing; workshopFor(d.currentJob.name).buildCost) foreach(n; 0 .. ing.count) {
    auto found = d.carrying.filter!(cid => app.world.drops.itemOf(cid).matchDemand(ing.cls, ing.item));
    if(found.empty) continue;
    app.consumeCarried(d, found.front);
  }
  app.placeWorkshop(d.currentJob.name, d.currentJob.targetTile);
}
