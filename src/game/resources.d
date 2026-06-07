/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

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

void injectResourceMeshes(ref GameApp app) {
  app.meshes.length = 0;
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    app.world.resources[ttype] = cast(uint)app.meshes.length;
    if(app.materials.length <= tt) app.materials ~= Material();  // only add material once
    app.meshes ~= Mesh([0, 0], cast(int)tt);  // reuse existing material slot
  }
}

void updateMaterials(ref GameApp app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    uint idx =  app.world.resources[ttype];
    app.materials[app.meshes[idx].mid].tid = app.textures.idx(resourceData(ttype).name ~ "_base");
    if((resourceData(ttype).meshName != "Blocks")) app.materials[app.meshes[idx].mid].nid = app.textures.idx(resourceData(ttype).name ~ "_normal");
  }
}
