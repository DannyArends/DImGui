/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : cleanup;
import commands : beginSingleTimeCommands, endSingleTimeCommands;
import textures : toRGBA, toGPU;
import images : createImage, cleanup, imageSize;
import io : fixPath;
import views : createImageView;

/** Glyph stores FreeType glyph data */
struct Glyph {
  int[2] sDim;    /// rendered bitmap width, height (includes SDF spread)
  int[2] aDim;    /// atlas x and y blit position
  int[2] bearing; /// bitmap_left, bitmap_top per-glyph offset from pen/baseline to bitmap's top-left
  int advance;
}

/** The GlyphAtlas structure holds links to the FreeType library/face, Glyphs, Texture and the atlas */
struct GlyphAtlas {
  string path;            /// Path of TTF file
  FT_Library ftLibrary;   /// FreeType library handle
  FT_Face face;           /// FreeType font face
  ubyte pointsize;        /// Font pointsize size
  int lineHeight;         /// Full line height (ascent + descent)
  Glyph[dchar] glyphs;    /// Associative array couples Glyph and dchar
  string atlas;           /// UTF-8 string of chars stored in the atlas
  Texture texture;        /// Holds the Texture structure containing the SDL surface and Vulkan buffers
  int ascent;             /// Font ascent
  int advance;            /// Font advance

  /** Get a specific glyph from the atlas */
  Glyph getGlyph(dchar letter) nothrow {
    if(letter in glyphs) return(glyphs[letter]);
    return(glyphs[0]);
  }

  /** Glyph texture X / Y postion */
  @property float tX(Glyph glyph) { return(glyph.aDim[0] / cast(float)(texture.width)); }
  @property float tY(Glyph glyph) { return(glyph.aDim[1] / cast(float)(texture.height)); }
  /** Glyph texture X / Y extent (UV width) */
  @property float tXo(Glyph glyph) { return(glyph.sDim[0] / cast(float)(texture.width)); }
  @property float tYo(Glyph glyph) { return(glyph.sDim[1] / cast(float)(texture.height)); }
  /** X postion of the glyph, when on column col — pen position plus this glyph's real left bearing */
  @property float pX(Glyph glyph, size_t col) { return(cast(float)(col) * glyph.advance + glyph.bearing[0]); }
  /** Y postion of the glyph, when on line[0] out of line[1] — bottom of the bitmap, using the real
   * bitmap_top (distance baseline-to-bitmap-top) minus the bitmap's own height for the bottom edge. */
  @property float pY(Glyph glyph, size_t[2] line) {
    return(cast(float)(line[1] - line[0]) * lineHeight + (glyph.bearing[1] - glyph.sDim[1]));
  }
  /** Scaled quad width/height for a glyph at the given glyphscale */
  @property float qW(Glyph glyph, float glyphscale) { return(glyph.sDim[0] / glyphscale); }
  @property float qH(Glyph glyph, float glyphscale) { return(glyph.sDim[1] / glyphscale); }
  alias texture this;
}

/** Loads a GlyphAtlas from file */
void loadGlyphs(ref App app, string filename = "data/fonts/Roboto-M.ttf", ubyte pointsize = 48, dchar to = '\U000000FF', uint dim = 1024) {
  filename = fixPath(filename);
  if(app.verbose) SDL_Log("loadGlyphAtlas: %s", toStringz(filename));
  app.glyphAtlas = GlyphAtlas(filename);
  app.glyphAtlas.pointsize = (pointsize == 0) ? 12 : pointsize;

  FT_Init_FreeType(&app.glyphAtlas.ftLibrary);

  int spread = 8;
  int overlaps = 1;   // handle self-intersecting contours — likely fixes the seam artifacts we saw
  FT_Property_Set(app.glyphAtlas.ftLibrary, "sdf", "spread", &spread);
  FT_Property_Set(app.glyphAtlas.ftLibrary, "sdf", "overlaps", &overlaps);

  if(FT_New_Face(app.glyphAtlas.ftLibrary, toStringz(filename), 0, &app.glyphAtlas.face)) {
    SDL_Log("Error loading FreeType face %s\n", toStringz(filename));
    abort();
  }
  FT_Set_Pixel_Sizes(app.glyphAtlas.face, 0, app.glyphAtlas.pointsize);

  app.createGlyphAtlas(to, dim);
  FT_Done_Library(app.glyphAtlas.ftLibrary);
}

/** Blit an 8-bit grayscale FreeType SDF bitmap into the atlas as white RGB + alpha=value */
void blitSDFGlyph(ref App app, FT_Bitmap bmp, int x, int y) {
  if(SDL_MUSTLOCK(app.glyphAtlas.surface)) SDL_LockSurface(app.glyphAtlas.surface);
  ubyte* dst = cast(ubyte*)app.glyphAtlas.surface.pixels;
  int dstPitch = app.glyphAtlas.surface.pitch;
  for(uint row = 0; row < bmp.rows; row++) { for(uint col = 0; col < bmp.width; col++) {
    ubyte v = bmp.buffer[row * bmp.pitch + col];
    size_t o = (y + row) * dstPitch + (x + col) * 4;
    dst[o+0] = 255; dst[o+1] = 255; dst[o+2] = 255; dst[o+3] = v;
  } }
  if(SDL_MUSTLOCK(app.glyphAtlas.surface)) SDL_UnlockSurface(app.glyphAtlas.surface);
}

/** Populates the GlyphAtlas with Glyphs to dchar in our atlas */
void createGlyphAtlas(ref App app, dchar to = '\U00000FFF', uint dim = 1024) {
  if(app.trace) SDL_Log("createGlyphAtlas");
  MonoTime sT = MonoTime.currTime;
  auto face = app.glyphAtlas.face;
  app.glyphAtlas.ascent = face.size.metrics.ascender >> 6;
  app.glyphAtlas.lineHeight = face.size.metrics.height >> 6;

  app.glyphAtlas.texture = Texture(app.glyphAtlas.path, dim, dim, SDL_CreateSurface(dim, dim, SDL_PIXELFORMAT_RGBA32));
  SDL_SetSurfaceBlendMode(app.glyphAtlas.surface, SDL_BLENDMODE_NONE);
  app.glyphAtlas.width = app.glyphAtlas.height = dim;

  uint atlasloc = 0;
  int penY = 0, rowMaxH = 0;
  app.glyphAtlas.atlas = [];
  dchar c = '\U00000000';
  while (c <= to) {
    FT_UInt glyphIndex = FT_Get_Char_Index(face, cast(uint)c);
    if (glyphIndex != 0 && !(c == '\t' || c == '\r' || c == '\n')) {
      if(FT_Load_Glyph(face, glyphIndex, FT_LOAD_DEFAULT)) { c++; continue; }
      if(FT_Render_Glyph(face.glyph, FT_RENDER_MODE_SDF)) { c++; continue; }

      auto bmp = face.glyph.bitmap;
      Glyph glyph = Glyph();
      glyph.sDim = [bmp.width, bmp.rows];
      glyph.bearing = [face.glyph.bitmap_left, face.glyph.bitmap_top];
      glyph.advance = face.glyph.advance.x >> 6;

      if (atlasloc + bmp.width >= app.glyphAtlas.width) { atlasloc = 0; penY += rowMaxH; rowMaxH = 0; }
      if (penY + bmp.rows > app.glyphAtlas.height) {
        SDL_Log("WARNING: GlyphAtlas overflow at (and after) character %d", c);
        break;
      }
      if (cast(int)bmp.rows > rowMaxH) rowMaxH = bmp.rows;
      if (app.glyphAtlas.advance < glyph.advance) app.glyphAtlas.advance = glyph.advance;
      glyph.aDim = [atlasloc, penY];
      app.glyphAtlas.glyphs[c] = glyph;
      app.glyphAtlas.atlas ~= c;
      app.blitSDFGlyph(bmp, atlasloc, penY);
      atlasloc += bmp.width;
    }
    c++;
  }

  auto time = (MonoTime.currTime - sT).total!"msecs"();
  if (app.verbose) {
    SDL_Log("%d unicode glyphs", app.glyphAtlas.glyphs.length);
    SDL_Log("FontAscent: %d, FontAdvance: %d", app.glyphAtlas.ascent, app.glyphAtlas.advance);
  }
  SDL_Log("%d/%d Glyphs [%d x %d] in %d msecs\n", app.glyphAtlas.glyphs.length, c, dim, dim, time);
}

/** Create a TextureImage layout and view from the SDL_Surface and adds it to the App.textureArray */
void uploadFont(ref App app) {
  if(app.verbose) SDL_Log("Uploading Font Texture to GPU");
  GPUAllocation staging;
  auto commandBuffer = app.beginSingleTimeCommands(app.transferPool);
  app.toGPU(commandBuffer, app.glyphAtlas.texture, staging, VK_FORMAT_R8G8B8A8_UNORM);
  app.endSingleTimeCommands(commandBuffer, app.transfer);
  app.cleanup(staging);
  app.textures ~= app.glyphAtlas.texture;
  app.mainDeletionQueue.add((){ app.cleanup(app.glyphAtlas.texture); });
}
