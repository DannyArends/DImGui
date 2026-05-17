/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : dir, fixPath;
import textures : transferTextureAsync, idx, toRGBA;
import images : deAllocate;

struct ResourceT {
  string name      = "None";
  bool traversable = false;
  bool buildable   = false;
  ubyte maxStack   = 1;
  float cost       = 0.0f;
  string meshName  = "Blocks";
  float dropScale  = 1.0f;
  Colors color     = Colors.white;
}

struct ResourceAtlas {
  int[ResourceType] tid;
  int[ResourceType] nid;
}

void injectResourceMeshes(ref App app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    Mesh m;
    m.mid = tt;  // <-- add this
    m.tid = app.resourceAtlas.tid.get(cast(ResourceType)tt, -1);
    m.nid = app.resourceAtlas.nid.get(cast(ResourceType)tt, -1);
    app.meshes ~= m;
  }
}

void updateResourceAtlas(ref App app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    app.resourceAtlas.tid[ttype] = app.textures.idx(resourceData(ttype).name ~ "_base");
    app.resourceAtlas.nid[ttype] = app.textures.idx(resourceData(ttype).name ~ "_normal");
    if (tt >= app.materials.length) app.materials.length = tt + 1;
    app.materials[tt].tid = app.resourceAtlas.tid[ttype];
    app.materials[tt].nid = app.resourceAtlas.nid[ttype];
    SDL_Log("material[%d] tid=%d nid=%d (mesh.tid=%d mesh.nid=%d)",
            tt, app.materials[tt].tid, app.materials[tt].nid,
            app.resourceAtlas.tid[ttype], app.resourceAtlas.nid[ttype]);
  }
  app.buffers["MeshMatrices"].dirty[] = true;
  app.buffers["MaterialBuffer"].dirty[] = true;
}
