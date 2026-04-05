/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import io : dir, fixPath;
import textures : transferTextureAsync, toRGBA;
import images : deAllocate;

struct TileT {
  string name       = "Stone_01";
  bool traversable  = false;
  float cost        = 0.0f;
}
 
enum TileType : TileT {
  None   = TileT("Stone_01", false, 0.0f),
  Lava   = TileT("Lava_01", false, 0.0f),
  Water  = TileT("Water_01", false, 0.0f),
  Sand   = TileT("Sand_01", true,  1.5f),
  Gravel = TileT("Gravel_01", true,  1.6f),
  Grass  = TileT("Grass_01", true,  1.2f),
  Forest = TileT("Forest_Ground_01", true,  1.5f),
  Stone  = TileT("Stone_01", true,  1.8f),
  Ice    = TileT("Ice_01", true,  1.0f),
  Snow   = TileT("Stone_03", true,  1.6f),
}
 
@nogc pure TileType heightToTile(float h) nothrow {
  if (h < 0.05f) return TileType.Lava;
  if (h < 0.15f) return TileType.Sand;
  if (h < 0.25f) return TileType.Gravel;
  if (h < 0.50f) return TileType.Grass;
  if (h < 0.65f) return TileType.Forest;
  if (h < 0.80f) return TileType.Stone;
  if (h < 0.90f) return TileType.Ice;
  return TileType.Snow;
}

struct TileAtlas {
  int[2][2][string] uv;
  uint size;
}

float[2] tileUV(ref TileAtlas ta, string name, bool right, bool bottom) nothrow {
  if (!(name in ta.uv)) return [right ? 1.0f : 0.0f, bottom ? 1.0f : 0.0f];
  float u = (right  ? ta.uv[name][0][1] : ta.uv[name][0][0]) / cast(float)(ta.size);
  float v = (bottom ? ta.uv[name][1][1] : ta.uv[name][1][0]) / cast(float)(ta.size);
  return [u, v];
}

void createTileAtlas(ref App app, string folder = "data/textures/3DTextures.me", int size = 512, int tileSize = 64) {
  folder = cast(string)fromStringz(fixPath(toStringz(folder)));
  if (app.verbose) SDL_Log("createTileAtlas: %s", toStringz(folder));
 
  TileAtlas ta;
  ta.size = size;

  string[] files = dir(toStringz(folder), "*_base*");
  SDL_Surface*[string] surfaces;
 
  int tx = 0, ty = 0, rowH = 0;
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

    if (tx + s.w > size) { ty += rowH; rowH = 0; tx = 0; }
    ta.uv[tname] = [[tx, tx + s.w], [ty, ty + s.h]];
    if (s.h > rowH) rowH = s.h;
    tx += s.w;
    surfaces[tname] = s;
  }

  auto atlas = SDL_CreateSurface(size, size, SDL_PIXELFORMAT_RGBA32);
  SDL_SetSurfaceBlendMode(atlas, SDL_BLENDMODE_NONE);
  foreach (tname; ta.uv.keys) {
    SDL_Rect dst = { ta.uv[tname][0][0], ta.uv[tname][1][0], ta.uv[tname][0][1] - ta.uv[tname][0][0], ta.uv[tname][1][1] - ta.uv[tname][1][0] };
    SDL_BlitSurface(surfaces[tname], null, atlas, &dst);
    SDL_DestroySurface(surfaces[tname]);
  }

  auto texture = Texture(folder, size, size, atlas);
  app.transferTextureAsync(texture);
  SDL_DestroySurface(atlas);
  app.mainDeletionQueue.add((){ app.deAllocate(texture); });
  app.tileAtlas = ta;
  if (app.verbose) SDL_Log("createTileAtlas: %d tiles [%dx%d]", ta.uv.keys.length, size, size);
}
