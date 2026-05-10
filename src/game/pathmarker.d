/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : position;

/** Rebuild path marker instances from all dwarf paths */
void syncPathMarkers(ref World world, bool showPaths = false) {
  if(world.pathMarkers is null || world.dwarves is null) return;
  world.pathMarkers.instances = [];
  if(showPaths) {
    foreach(ref d; world.dwarves) {
      foreach(l; d.path) {
        DrawInstance inst = DrawInstance([0, 0, d.colorID, 0]);
        inst = position(inst, [l[0], l[1] - 0.4f, l[2]]);
        world.pathMarkers.instances ~= inst;
      }
    }
  }
  world.pathMarkers.markDirty();
}