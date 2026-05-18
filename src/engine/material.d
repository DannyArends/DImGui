/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import textures : idx;

shared uint muid = 0;

struct Material {
  uint mid;
  int tid = -1;
  int nid = -1;
  int oid = -1;

  this(int tid, int nid, int oid) {
    this.mid = atomicOp!"+="(muid, 1) - 1;
    this.tid = tid;
    this.nid = nid;
    this.oid = oid;
  }
}

void registerAMaterials(ref App app, ref Geometry object) {
  foreach(ref mesh; object.meshes) {
    if(mesh.mid < 0 || mesh.mid >= object.materials.length) continue;
    mesh.mat = mesh.mid;  // save local index before remap
    app.materials ~= Material(-1, -1, -1);
    mesh.mid = app.materials[$-1].mid;
  }
}

