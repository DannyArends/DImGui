/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

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

struct MaterialList {
  Material[] materials;
  ulong capacity = 256;
  alias materials this;
}

int getOrCreateMaterial(ref App app, int tid, int nid, int oid) {
  Material m = Material(tid, nid, oid);
  app.materials ~= m;
  return m.mid;
}