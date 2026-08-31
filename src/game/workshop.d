/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : itemOf;
import feature : rebuildAllFeatures;
import jobs : cleanWorksiteJob, consumeCarried, evictDwarfAt, jobQueue, pickupJob;
import lattice : chunkCoord;
import resources : matchDemand;
import tile : getTileAt, isTileOccupied;

alias Workshops = Features;

/** The [WORKSHOP] raw of this name. */
ref immutable(RawT) workshopFor(string name) {
  foreach(ref w; workshopTable) { if(w.name == name) { return(w); } }
  assert(0, "no [WORKSHOP] named " ~ name);
}

/** Root workshop `name` at `tile`: inject it, mark the chunk edited, rebuild instances. */
void placeWorkshop(ref GameApp app, string name, int[3] tile) {
  int[3] coord = app.world.chunkCoord(tile);
  app.world.features[name][coord] ~= Feature(tile, 1);
  app.world.features.modified[coord] = true;
  app.rebuildAllFeatures();
}

/** Place a workshop at an empty tile: haul its buildCost, consume it, then root the workshop. */
Job!Dwarf buildWorkshopJob(string name, int[3] targetTile) {
  Job!Dwarf[] prereqs = [cleanWorksiteJob(targetTile)];
  foreach(ing; workshopFor(name).buildCost) foreach(n; 0 .. ing.count) prereqs ~= pickupJob(noTile, ing.cls, ing.item);
  return Job!Dwarf(name, targetTile, Substance.None, prereqs,
    isValid: (ref GameApp app, ref Job!Dwarf j){ return(app.world.getTileAt(j.targetTile) == ResourceType.None); },
    onArrive: (ref GameApp app, ref Dwarf d) {
      if(app.isTileOccupied(d.currentJob.targetTile)) {
        if(!app.evictDwarfAt(d.currentJob.targetTile)){ d.currentJob.onFail(app, d); }
        return;
      }
      foreach(ing; workshopFor(d.currentJob.name).buildCost) { foreach(n; 0 .. ing.count) {
        auto found = d.carrying.filter!(cid => app.world.drops.itemOf(cid).matchDemand(ing.cls, ing.item));
        if(found.empty) continue;
        app.consumeCarried(d, found.front);
      } }
      app.placeWorkshop(d.currentJob.name, d.currentJob.targetTile);
      d.onSubJobComplete(app);
    },
    onFail: (ref GameApp app, ref Dwarf d) {
      foreach(slot, ref s; d.inventory) { if(!s.empty) d.drop(app.world.drops, slot); }
      auto newJob = buildWorkshopJob(d.currentJob.name, d.currentJob.targetTile);
      newJob.failedBy = d.jobStack[$-1].failedBy.dup;
      newJob.failedBy[d.uid] = true;
      jobQueue ~= newJob;
      d.clearGoal();
    }
  );
}
