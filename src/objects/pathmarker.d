/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : position;

class PathMarkers : Cylinder {
  this() {
    super(0.1f, 0.2f, 6);
    initInstanced(() => "PathMarkers");
  }
}

/** Rebuild path marker instances from all dwarf paths */
void syncPathMarkers(ref App app) {
  if(app.world.pathMarkers is null || app.world.dwarves is null) return;
  app.world.pathMarkers.instances = [];
  if(app.showPaths) {
    foreach(ref d; app.world.dwarves) {
      foreach(ref wp; d.path) {
        DrawInstance inst = DrawInstance([0, 0, d.colorID, 0]);
        inst = position(inst, [wp[0], wp[1] - 0.4f, wp[2]]);
        app.world.pathMarkers.instances ~= inst;
      }
    }
  }
  app.world.pathMarkers.markDirty();
}