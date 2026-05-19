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

void injectResourceMeshes(ref App app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    app.materials ~= Material(cast(uint)app.materials.length, -1, -1, -1);
    app.meshes ~= Mesh([0, 0], app.materials[$-1].mid);
  }
}

void updateResourceAtlas(ref App app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    app.materials[app.meshes[tt].mid].tid = app.textures.idx(resourceData(ttype).name ~ "_base");
    app.materials[app.meshes[tt].mid].nid = app.textures.idx(resourceData(ttype).name ~ "_normal");
  }
  app.buffers["MaterialBuffer"].dirty[] = true;
}
