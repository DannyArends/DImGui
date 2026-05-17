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
    auto ttype = cast(ResourceType)tt;
    app.materials ~= Material(app.resourceAtlas.tid.get(ttype, -1), app.resourceAtlas.nid.get(ttype, -1), -1);
    app.meshes ~= Mesh([0, 0], app.materials[$-1].mid);
  }
}

void updateResourceAtlas(ref App app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    app.resourceAtlas.tid[ttype] = app.textures.idx(resourceData(ttype).name ~ "_base");
    app.resourceAtlas.nid[ttype] = app.textures.idx(resourceData(ttype).name ~ "_normal");
    app.materials[app.meshes[tt].mid].tid = app.resourceAtlas.tid[ttype];
    app.materials[app.meshes[tt].mid].nid = app.resourceAtlas.nid[ttype];
  }
  app.buffers["MeshMatrices"].dirty[] = true;
  app.buffers["MaterialBuffer"].dirty[] = true;
}
