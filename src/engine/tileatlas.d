/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import io : dir, fixPath;
import textures : transferTextureAsync, idx, toRGBA;
import images : deAllocate;

struct TileT {
  string name = "None";
  bool traversable  = false;
  float cost = 0.0f;
}

enum TileType : ubyte {
  None, Lava, Water, Path08, Sand01, Sand02, Sand03, Sand05, Gravel, Moss01, Ground08, Grass01, Grass02, Grass03, Forest01, Forest02, Stone, Ice01, Snow
}

immutable TileT[TileType] tileData;
shared static this() {
  tileData = [
    TileType.None: TileT("None", false, 0.0f),
    TileType.Lava: TileT("Lava_01", false, 0.0f),
    TileType.Water: TileT("Water_01", false, 0.0f),
    TileType.Path08: TileT("Path_08", true,  1.5f),
    TileType.Sand01: TileT("Sand_01", true,  1.5f),
    TileType.Sand02: TileT("Sand_02", true,  1.5f),
    TileType.Sand03: TileT("Sand_03", true,  1.5f),
    TileType.Sand05: TileT("Sand_05", true,  1.5f),
    TileType.Gravel: TileT("Gravel_01", true,  1.6f),
    TileType.Moss01: TileT("Moss_01", true,  1.2f),
    TileType.Ground08: TileT("Ground_08", true,  1.2f),
    TileType.Grass01: TileT("Grass_01", true,  1.2f),
    TileType.Grass02: TileT("Grass_02", true,  1.2f),
    TileType.Grass03: TileT("Grass_03", true,  1.2f),
    TileType.Forest01: TileT("Forest_Ground_01", true,  1.5f),
    TileType.Forest02: TileT("Hedge_01", true,  1.5f),
    TileType.Stone: TileT("Stone_01", true,  1.8f),
    TileType.Ice01: TileT("Ice_01", true,  1.0f),
    TileType.Snow: TileT("Ice_03", true,  1.6f),
  ];
}

@nogc pure TileType heightToTile(float h, float t) nothrow {
  if (h < 0.05f) return TileType.Lava;
  if (h < 0.15f){ TileType[2] variants = [TileType.Stone, TileType.Gravel]; return variants[cast(uint)(t * 2) % 2]; }
  if (h < 0.25f){ TileType[4] variants = [TileType.Sand01, TileType.Sand02, TileType.Sand03, TileType.Sand05]; return variants[cast(uint)(t * 4) % 4]; }
  if (h < 0.35f){ TileType[5] variants = [TileType.Gravel, TileType.Sand02, TileType.Grass01, TileType.Path08, TileType.Grass02]; return variants[cast(uint)(t * 5) % 5]; }
  if (h < 0.50f){ TileType[3] variants = [TileType.Grass01, TileType.Grass02, TileType.Grass03]; return variants[cast(uint)(t * 3) % 3]; }
  if (h < 0.65f){ TileType[3] variants = [TileType.Moss01, TileType.Forest01, TileType.Forest02]; return variants[cast(uint)(t * 3) % 3]; }
  if (h < 0.80f) return TileType.Stone;
  if (h < 0.90f) return TileType.Ice01;
  return TileType.Snow;
}

struct TileAtlas {
  int[TileType] tid;
  int[TileType] nid;
}

void injectTileMeshes(ref App app) {
  foreach (tt; 0 .. cast(int)TileType.max + 1) {
    Mesh m;
    m.tid = app.tileAtlas.tid.get(cast(TileType)tt, -1);
    m.nid = app.tileAtlas.nid.get(cast(TileType)tt, -1);
    app.meshes ~= m;
  }
}

void updateTileAtlas(ref App app) {
  foreach (tt; 0 .. cast(int)TileType.max + 1) {
    auto ttype = cast(TileType)tt;
    app.tileAtlas.tid[ttype] = app.textures.idx(tileData[ttype].name ~ "_base");
    app.tileAtlas.nid[ttype] = app.textures.idx(tileData[ttype].name ~ "_normal");
  }
  app.buffers["MeshMatrices"].dirty[] = true;
}