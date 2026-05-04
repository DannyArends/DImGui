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
}

enum ResourceType : ubyte {
  @ResourceT("None",             false, false, 0,  0.0f, "Blocks",  1.0f)  None,
  @ResourceT("Lava_01",          false, false, 0,  0.0f, "Blocks",  1.0f)  Lava,
  @ResourceT("Water_01",         false, false, 0,  0.0f, "Blocks",  1.0f)  Water,
  @ResourceT("Sand_01",          true,  true,  1,  2.0f, "Blocks",  1.0f)  Sand01,
  @ResourceT("Sand_02",          true,  true,  1,  2.0f, "Blocks",  1.0f)  Sand02,
  @ResourceT("Sand_03",          true,  true,  1,  2.5f, "Blocks",  1.0f)  Sand03,
  @ResourceT("Sand_05",          true,  true,  1,  3.5f, "Blocks",  1.0f)  Sand05,
  @ResourceT("Gravel_01",        true,  true,  1,  1.5f, "Blocks",  1.0f)  Gravel,
  @ResourceT("Moss_01",          true,  true,  1,  1.0f, "Blocks",  1.0f)  Moss01,
  @ResourceT("Ground_08",        true,  true,  1,  1.0f, "Blocks",  1.0f)  Ground08,
  @ResourceT("Grass_01",         true,  true,  1,  1.0f, "Blocks",  1.0f)  Grass01,
  @ResourceT("Grass_02",         true,  true,  1,  1.0f, "Blocks",  1.0f)  Grass02,
  @ResourceT("Grass_03",         true,  true,  1,  1.0f, "Blocks",  1.0f)  Grass03,
  @ResourceT("Grass_04",         true,  true,  1,  1.0f, "Blocks",  1.0f)  Grass04,
  @ResourceT("Forest_Ground_01", true,  true,  1,  2.0f, "Blocks",  1.0f)  Forest01,
  @ResourceT("Jungle_01",        true,  true,  1,  2.9f, "Blocks",  1.0f)  Forest02,
  @ResourceT("Stone_01",         true,  true,  1,  3.0f, "Blocks",  1.0f)  Stone01,
  @ResourceT("Stone_02",         true,  true,  1,  2.0f, "Blocks",  1.0f)  Stone02,
  @ResourceT("Stone_03",         true,  true,  1,  2.0f, "Blocks",  1.0f)  Stone03,
  @ResourceT("Stone_05",         true,  true,  1,  2.0f, "Blocks",  1.0f)  Stone05,
  @ResourceT("Ice_01",           true,  true,  1,  4.0f, "Blocks",  1.0f)  Ice01,
  @ResourceT("Ice_03",           true,  true,  1,  4.5f, "Blocks",  1.0f)  Snow,
  @ResourceT("Wood_03",          true,  true,  1,  1.0f, "Blocks",  1.0f)  Wood,
  @ResourceT("Hedge_01",         false, false, 0,  0.0f, "Blocks",  1.0f)  Leaves,
  @ResourceT("Berry",            false, false, 16, 0.0f, "Berries", 0.5f) Berry
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

@nogc pure ResourceType heightToResource(float h, float t) nothrow {
  if (h < 0.05f) return ResourceType.Lava;
  if (h < 0.15f){ ResourceType[3] variants = [ResourceType.Stone01, ResourceType.Gravel, ResourceType.Moss01]; return variants[cast(uint)(t * 3) % 3]; }
  if (h < 0.25f){ ResourceType[4] variants = [ResourceType.Sand01, ResourceType.Sand02, ResourceType.Sand03, ResourceType.Sand05]; return variants[cast(uint)(t * 4) % 4]; }
  if (h < 0.35f){ ResourceType[4] variants = [ResourceType.Forest02, ResourceType.Sand02, ResourceType.Forest01, ResourceType.Grass02]; return variants[cast(uint)(t * 4) % 4]; }
  if (h < 0.50f){ ResourceType[4] variants = [ResourceType.Grass01, ResourceType.Grass02, ResourceType.Grass01, ResourceType.Grass04]; return variants[cast(uint)(t * 4) % 4]; }
  if (h < 0.70f){ ResourceType[4] variants = [ResourceType.Grass04, ResourceType.Grass01, ResourceType.Stone02, ResourceType.Forest02]; return variants[cast(uint)(t * 4) % 4]; }
  if (h < 0.80f){ ResourceType[3] variants = [ResourceType.Stone01, ResourceType.Stone05, ResourceType.Forest01]; return variants[cast(uint)(t * 3) % 3]; }
  if (h < 0.85f) return ResourceType.Stone01;
  if (h < 0.90f) return ResourceType.Ice01;
  return ResourceType.Snow;
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
