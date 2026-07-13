/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import matrix : translate;

struct Paths {
  PathMarkers markers;
  PathRequest[] pending;
}

/** Rebuild path marker instances from all dwarf paths */
void syncPathMarkers(ref World world, bool showPaths = false) {
  if(world.paths.markers is null || world.dwarves is null) return;
  world.paths.markers.instances = [];
  if(showPaths) {
    foreach(ref d; world.dwarves) {
      foreach(l; d.path) { world.paths.markers.instances ~= DrawInstance(translate([l[0], l[1] - 0.4f, l[2]]), -1, d.color); }
    }
  }
  world.paths.markers.syncInstances();
}
