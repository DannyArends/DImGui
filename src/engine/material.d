/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import textures : idx;

struct Material {
  int tid = -1;
  int nid = -1;
  int oid = -1;
  int pad = 0;
}

/** Register a global material slot for every mesh with a bindable material (call once at load) */
void registerMaterials(ref App app, ref Geometry object) {
  foreach(ref mesh; object.meshes) {
    if(object.materials.length == 0) continue;                 // no material to bind
    if(mesh.mid >= object.materials.length) continue;          // invalid local index
    if(mesh.mid >= 0) mesh.mat = mesh.mid;                     // assimp: save local index (procedural keeps its mat)
    mesh.mid = cast(int)(app.materials.length);
    app.materials ~= Material();
  }
  app.buffers["MaterialBuffer"].invalidate();
}

/** Idempotent top-up: give a global material slot to any mesh still lacking one (safe to repeat) */
void ensureMaterial(ref App app, ref Geometry object) {
  foreach(ref mesh; object.meshes) {
    if(mesh.mid >= 0) continue;
    mesh.mid = cast(int)(app.materials.length);
    app.materials ~= Material();
  }
  app.buffers["MaterialBuffer"].invalidate();
}
