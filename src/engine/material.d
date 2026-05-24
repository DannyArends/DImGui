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
  }
  app.buffers["MaterialBuffer"].dirty[] = true;
}

void updateMaterials(ref App app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    app.materials[app.meshes[tt].mid].tid = app.textures.idx(resourceData(ttype).name ~ "_base");
    app.materials[app.meshes[tt].mid].nid = app.textures.idx(resourceData(ttype).name ~ "_normal");
  }
  app.buffers["MaterialBuffer"].dirty[] = true;
}
