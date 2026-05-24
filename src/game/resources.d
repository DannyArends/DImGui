/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import game : GameApp;
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
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    app.meshes ~= Mesh([0, 0], cast(int)(app.materials.length));
    app.materials ~= Material();
  }
}
