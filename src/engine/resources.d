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

enum ResourceType : ubyte {
  @ResourceT("None",             false, false, 0,  0.0f, "Blocks",  1.0f, Colors.white)  None,
  @ResourceT("Lava_01",          false, false, 0,  0.0f, "Blocks",  1.0f, Colors.white)  Lava,
  @ResourceT("Water_01",         false, false, 0,  0.0f, "Blocks",  1.0f, Colors.white)  Water,
  @ResourceT("Sand_01",          true,  true,  1,  2.0f, "Blocks",  1.0f, Colors.white)  Sand01,
  @ResourceT("Sand_02",          true,  true,  1,  2.0f, "Blocks",  1.0f, Colors.white)  Sand02,
  @ResourceT("Sand_03",          true,  true,  1,  2.5f, "Blocks",  1.0f, Colors.white)  Sand03,
  @ResourceT("Sand_05",          true,  true,  1,  3.5f, "Blocks",  1.0f, Colors.white)  Sand05,
  @ResourceT("Gravel_01",        true,  true,  1,  1.5f, "Blocks",  1.0f, Colors.white)  Gravel,
  @ResourceT("Moss_01",          true,  true,  1,  1.0f, "Blocks",  1.0f, Colors.white)  Moss01,
  @ResourceT("Ground_08",        true,  true,  1,  1.0f, "Blocks",  1.0f, Colors.white)  Ground08,
  @ResourceT("Grass_01",         true,  true,  1,  1.0f, "Blocks",  1.0f, Colors.white)  Grass01,
  @ResourceT("Grass_02",         true,  true,  1,  1.0f, "Blocks",  1.0f, Colors.white)  Grass02,
  @ResourceT("Grass_03",         true,  true,  1,  1.0f, "Blocks",  1.0f, Colors.white)  Grass03,
  @ResourceT("Grass_04",         true,  true,  1,  1.0f, "Blocks",  1.0f, Colors.white)  Grass04,
  @ResourceT("Forest_Ground_01", true,  true,  1,  2.0f, "Blocks",  1.0f, Colors.white)  Forest01,
  @ResourceT("Jungle_01",        true,  true,  1,  2.9f, "Blocks",  1.0f, Colors.white)  Forest02,
  @ResourceT("Stone_01",         true,  true,  1,  3.0f, "Blocks",  1.0f, Colors.white)  Stone01,
  @ResourceT("Stone_02",         true,  true,  1,  2.0f, "Blocks",  1.0f, Colors.white)  Stone02,
  @ResourceT("Stone_03",         true,  true,  1,  2.0f, "Blocks",  1.0f, Colors.white)  Stone03,
  @ResourceT("Stone_05",         true,  true,  1,  2.0f, "Blocks",  1.0f, Colors.white)  Stone05,
  @ResourceT("Ice_01",           true,  true,  1,  4.0f, "Blocks",  1.0f, Colors.white)  Ice01,
  @ResourceT("Ice_03",           true,  true,  1,  4.5f, "Blocks",  1.0f, Colors.white)  Snow,
  @ResourceT("Wood_03",          true,  true,  1,  1.0f, "Blocks",  1.0f, Colors.white)  Wood,
  @ResourceT("Hedge_01",         false, false, 0,  0.0f, "Blocks",  1.0f, Colors.white)  Leaves,
  @ResourceT("Berry",            false, false, 16, 0.0f, "Berries", 0.5f, Colors.crimson) Berry
}

/// Retrieve the ResourceT metadata for a given ResourceType
@nogc pure ResourceT resourceData(ResourceType rt) nothrow {
  switch(rt) {
    static foreach(member; __traits(allMembers, ResourceType)) {
      case __traits(getMember, ResourceType, member):
        return __traits(getAttributes, __traits(getMember, ResourceType, member))[0];
    }
    default: return ResourceT.init;
  }
}

struct ResourceAtlas {
  int[ResourceType] tid;
  int[ResourceType] nid;
}

void injectResourceMeshes(ref App app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    Mesh m;
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
  }
  app.buffers["MeshMatrices"].dirty[] = true;
}
