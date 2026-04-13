/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import io : dir, fixPath;
import textures : transferTextureAsync, toRGBA;
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
  int[2][2][string] uv;
  uint size;
}

@nogc pure float[2] tileUV(const TileAtlas ta, string name, bool right, bool bottom) nothrow {
  if (!(name in ta.uv)) return [right ? 1.0f : 0.0f, bottom ? 1.0f : 0.0f];
  float u = (right  ? ta.uv[name][0][1] : ta.uv[name][0][0]) / cast(float)(ta.size);
  float v = (bottom ? ta.uv[name][1][1] : ta.uv[name][1][0]) / cast(float)(ta.size);
  return [u, v];
}

@nogc pure float[4] tileUVTransform(const TileAtlas ta, string name) nothrow {
  float[2] tl = ta.tileUV(name, false, false);
  float[2] br = ta.tileUV(name, true,  true);
  return [tl[0], tl[1], br[0] - tl[0], br[1] - tl[1]];
}

void createTileAtlas(ref App app, string folder = "data/textures/3DTextures.me", int size = 1024, int tileSize = 128) {
  if (app.verbose) SDL_Log("createTileAtlas: %s", toStringz(folder));
 
  TileAtlas ta;
  ta.size = size;

  string[] files = dir(toStringz(folder), "*_base*");
  SDL_Surface*[string] surfaces;
 
  int tx = 0, ty = 0, rowH = 0, padding = 1;
  foreach (file; files) {
    string bname = stripExtension(baseName(file));
    auto sidx = bname.lastIndexOf("_base");
    if (sidx < 0) continue;
    string tname = bname[0 .. sidx];

    SDL_Surface* s = IMG_Load(toStringz(file));
    if (!s) { SDL_Log("createTileAtlas: failed %s", toStringz(file)); continue; }
    if (SDL_GetPixelFormatDetails(s.format).bits_per_pixel != 32) s.toRGBA();

    // Scale down to tileSize x tileSize
    SDL_Surface* scaled = SDL_CreateSurface(tileSize, tileSize, SDL_PIXELFORMAT_RGBA32);
    SDL_BlitSurfaceScaled(s, null, scaled, null, SDL_SCALEMODE_LINEAR);
    SDL_DestroySurface(s);
    s = scaled;

    if (tx + s.w + padding > size) { ty += rowH; rowH = 0; tx = 0; }
    ta.uv[tname] = [[tx+ padding, tx + s.w- padding], [ty+ padding, ty + s.h- padding]];
    if (s.h + padding > rowH) rowH = s.h + padding;
    tx += s.w + padding;
    surfaces[tname] = s;
  }

  auto atlas = SDL_CreateSurface(size, size, SDL_PIXELFORMAT_RGBA32);
  SDL_FillSurfaceRect(atlas, null, SDL_MapRGBA(SDL_GetPixelFormatDetails(atlas.format), null, 0, 0, 0, 255));
  SDL_SetSurfaceBlendMode(atlas, SDL_BLENDMODE_NONE);
  foreach (tname; ta.uv.keys) {
    SDL_Rect dst = { ta.uv[tname][0][0] - padding, ta.uv[tname][1][0] - padding, 
                     ta.uv[tname][0][1] - ta.uv[tname][0][0] + padding * 2, ta.uv[tname][1][1] - ta.uv[tname][1][0] + padding * 2 };
    SDL_BlitSurface(surfaces[tname], null, atlas, &dst);
    SDL_DestroySurface(surfaces[tname]);
  }

  auto texture = Texture(folder, size, size, atlas);
  app.transferTextureAsync(texture);
  app.mainDeletionQueue.add((){ app.deAllocate(texture); });
  app.tileAtlas = ta;
  if (app.verbose) SDL_Log("createTileAtlas: %d tiles [%dx%d]", ta.uv.keys.length, size, size);
}

