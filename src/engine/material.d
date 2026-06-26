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

void registerAMaterials(ref App app, ref Geometry object) {
  foreach(ref mesh; object.meshes) {
    if(mesh.mid < 0 || mesh.mid >= object.materials.length) continue;
    mesh.mat = mesh.mid;  // save local index before remap
    mesh.mid = cast(int)(app.materials.length);
    app.materials ~= Material();
  }
}

void ensureMaterial(ref App app, ref Geometry object) {
  foreach(ref mesh; object.meshes) {
    if(mesh.mid >= 0) continue;
    mesh.mid = cast(int)(app.materials.length);
    app.materials ~= Material();
    app.buffers["MaterialBuffer"].invalidate();
  }
}
