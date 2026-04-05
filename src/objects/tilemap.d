/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;
 
import io : dir, fixPath;
import textures : transferTextureAsync, toRGBA;
import images : deAllocate;
import tileatlas: tileUV, heightToTile;

class TileMap : Geometry {
  uint cols, rows, layers;
  float tileSize, layerHeight;
 
  this(ref App app, uint cols = 32, uint rows = 32, uint layers = 1, float tileSize = 1.0f, float layerHeight = 0.1f) {
    this.cols     = cols;
    this.rows     = rows;
    this.layers   = layers;
    this.tileSize = tileSize;
    this.layerHeight = layerHeight;
 
    uint nTiles = cols * rows * layers;
    vertices.length = nTiles * 4;
    indices.length  = nTiles * 6;

    uint vi = 0, ii = 0;                  /// Default all tiles to None
    for (uint z = 0; z < layers; z++) {
      for (uint y = 0; y < rows; y++) {
        for (uint x = 0; x < cols; x++) {
          float wx = (x - cols * 0.5f) * tileSize;
          float wy = z * layerHeight;
          float wz = (y - rows * 0.5f) * tileSize;
          writeTile(app, vi, ii, wx, wy, wz, TileType.None);
          vi += 4; ii += 6;
        }
      }
    }

    instances = [Instance()];
    meshes["TileMap"] = Mesh([0, cast(uint)vertices.length]);
    name = (){ return(typeof(this).stringof); };
  }
 
  /** Get vertex index for grid position */
  uint tileIndex(uint x, uint y, uint z = 0) nothrow {
    return ((z * rows + y) * cols + x) * 4;
  }
 
  /** Write a single tile's 4 vertices + 6 indices in-place */
  void writeTile(ref App app, uint vi, uint ii, float wx, float wy, float wz, TileType tile) {
    if (tile == TileType.None) { indices[ii+0..ii+6] = vi; return; }

    float hs = tileSize * 0.5f;
    float[2] uvTR = app.tileAtlas.tileUV(tile.name, true,  false);
    float[2] uvBR = app.tileAtlas.tileUV(tile.name, true,  true);
    float[2] uvBL = app.tileAtlas.tileUV(tile.name, false, true);
    float[2] uvTL = app.tileAtlas.tileUV(tile.name, false, false);
 
    // Flat quad in XZ plane, Y is height — matches Square winding
    vertices[vi+0] = Vertex([wx+hs, wy, wz-hs], uvTR, [1.0f, 1.0f, 1.0f, 1.0f]);
    vertices[vi+1] = Vertex([wx-hs, wy, wz-hs], uvTL, [1.0f, 1.0f, 1.0f, 1.0f]);
    vertices[vi+2] = Vertex([wx-hs, wy, wz+hs], uvBL, [1.0f, 1.0f, 1.0f, 1.0f]);
    vertices[vi+3] = Vertex([wx+hs, wy, wz+hs], uvBR, [1.0f, 1.0f, 1.0f, 1.0f]);
 
    indices[ii+0] = vi+0; indices[ii+1] = vi+2; indices[ii+2] = vi+1;
    indices[ii+3] = vi+0; indices[ii+4] = vi+3; indices[ii+5] = vi+2;
  }
}


void applyHeightmap(ref App app, TileMap map, string heightmapPath) {
  SDL_Surface* hmap = IMG_Load(fixPath(toStringz(heightmapPath)));
  if (!hmap) { SDL_Log("applyHeightmap: failed %s", toStringz(heightmapPath)); return; }
 
  for (uint y = 0; y < map.rows; y++) {
    for (uint x = 0; x < map.cols; x++) {
      float nx = x / cast(float)(map.cols);
      float ny = y / cast(float)(map.rows);
      float h = sampleAlpha(hmap, nx, ny);
      uint  top = cast(uint)(h * (map.layers - 1));

      for (uint z = 0; z <= top; z++) {
        TileType tile;
        if (z == top)       tile = heightToTile(h);    /// surface tile
        else if (z == 0)    tile = TileType.Lava;      /// bottom always lava
        else                tile = TileType.Stone;     /// fill with stone

        uint vi = map.tileIndex(x, y, z);
        uint ii = (vi / 4) * 6;
        float wx = (x - map.cols * 0.5f) * map.tileSize;
        float wy = z * map.layerHeight;
        float wz = (y - map.rows * 0.5f) * map.tileSize;
        map.writeTile(app, vi, ii, wx, wy, wz, tile);
      }
    }
  }
 
  SDL_DestroySurface(hmap);
  map.buffers[VERTEX] = false;
  map.buffers[INDEX]  = false;
}
 
private ubyte* samplePixel(SDL_Surface* s, float nx, float nz) {
  if (!s) return null;
  int px = cast(int)(nx * (s.w - 1));
  int pz = cast(int)(nz * (s.h - 1));
  if (px < 0) px = 0; if (px >= s.w) px = s.w - 1;
  if (pz < 0) pz = 0; if (pz >= s.h) pz = s.h - 1;
  return cast(ubyte*)(s.pixels) + pz * s.pitch + px * SDL_GetPixelFormatDetails(s.format).bytes_per_pixel;
}
 
float sampleAlpha(SDL_Surface* s, float nx, float nz) {
  if (!s) return 0.0f;
  ubyte* p = samplePixel(s, nx, nz);
  return p[3] / 255.0f;
}
 