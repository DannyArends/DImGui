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

/** Glyph stores SDL2_TTF glyph data */
struct Glyph {
  int[2] sDim;   /// rendered surface width, height  (includes SDF spread)
  int[2] aDim;   /// atlas x and y blit position
  int[2] mmX;    /// min & max X
  int[2] mmY;    /// min & max Y
  int advance;

  @property @nogc int gX() nothrow { return(advance - mmX[0]); }
  @property @nogc int gY() nothrow { return(mmY[1] - mmY[0]); }
}

/** The GlyphAtlas structure holds links to the TTF_Font, Glyphs, Texture and the atlas */
struct GlyphAtlas {
  string path;          /// Path of TTF file
  TTF_Font* ttf;        /// Pointer to the loaded TTF_Font
  ubyte pointsize;      /// Font pointsize size
  int lineHeight;       /// Full line height (ascent + descent)
  Glyph[dchar] glyphs;  /// Associative array couples Glyph and dchar
  string atlas;         /// UTF-8 string of chars stored in the atlas
  Texture texture;      /// Holds the Texture structure containing the SDL surface and Vulkan buffers
  int ascent;           /// Font ascent
  int miny;             /// Font miny
  int advance;          /// Font advance

  /** Get a specific glyph from the atlas */
  Glyph getGlyph(dchar letter) nothrow {
    if(letter in glyphs) return(glyphs[letter]);
    return(glyphs[0]);
  }

  /** Glyph texture X postion */
  @property float tX(Glyph glyph) { return(glyph.aDim[0] / cast(float)(texture.width)); }
  /** Glyph texture Y postion */
  @property float tY(Glyph glyph) { return(glyph.aDim[1] / cast(float)(texture.height)); }
  /** Glyph texture X extent (UV width) */
  @property float tXo(Glyph glyph) { return(glyph.sDim[0] / cast(float)(texture.width)); }
  /** Glyph texture Y extent (UV height) */
  @property float tYo(Glyph glyph) { return(glyph.sDim[1] / cast(float)(texture.height)); }
  /** X postion of the glyph, when on column col */
  @property float pX(Glyph glyph, size_t col) { return(cast(float)(col) * glyph.advance + glyph.mmX[0]); }
  /** Y postion of the glyph, when on line[0] out of line[1] */
  @property float pY(Glyph glyph, size_t[2] line) { return(cast(float)(line[1] - line[0]) * this.lineHeight + (this.ascent - glyph.mmY[1])); }
  /** Scaled quad width/height for a glyph at the given glyphscale */
  @property float qW(Glyph glyph, float glyphscale) { return(glyph.sDim[0] / glyphscale); }
  @property float qH(Glyph glyph, float glyphscale) { return(glyph.sDim[1] / glyphscale); }
  alias texture this;
}

/** Loads a GlyphAtlas from file */
void loadGlyphAtlas(ref App app, string filename = "data/fonts/FreeMono.ttf", ubyte pointsize = 40, dchar to = '\U000000FF', uint dim = 1024) {
  filename = fixPath(filename);
  if(app.verbose) SDL_Log("loadGlyphAtlas: %s", toStringz(filename));
  app.glyphAtlas = GlyphAtlas(filename);
  app.glyphAtlas.pointsize = (pointsize == 0)? 12 : pointsize;
  app.glyphAtlas.ttf = TTF_OpenFont(toStringz(filename), cast(float)app.glyphAtlas.pointsize);
  if (!app.glyphAtlas.ttf) {
    SDL_Log("Error by loading TTF_Font %s: %s\n", toStringz(filename), SDL_GetError());
    abort();
  }
  app.createGlyphAtlas(to, dim);
}

/** Populates the GlyphAtlas with Glyphs to dchar in our atlas */
void createGlyphAtlas(ref App app, dchar to = '\U00000FFF', uint dim = 1024) {
  if(app.trace) SDL_Log("createGlyphAtlas");
  MonoTime sT = MonoTime.currTime;
  app.glyphAtlas.ascent = TTF_GetFontAscent(app.glyphAtlas.ttf);
  app.glyphAtlas.lineHeight = TTF_GetFontHeight(app.glyphAtlas.ttf);

  TTF_SetFontSDF(app.glyphAtlas.ttf, true);
  app.glyphAtlas.texture = Texture(app.glyphAtlas.path, dim, dim, SDL_CreateSurface(dim, dim, SDL_PIXELFORMAT_RGBA32));
  SDL_SetSurfaceBlendMode(app.glyphAtlas.surface, SDL_BLENDMODE_NONE);
  app.glyphAtlas.width = app.glyphAtlas.height = dim;

  uint i, atlasloc = 0;
  int penY = 0, rowMaxH = 0;
  app.glyphAtlas.atlas = [];
  dchar c = '\U00000000';
  while (c <= to) {
    if (isValidDchar(c) && TTF_FontHasGlyph(app.glyphAtlas.ttf, cast(uint)(c)) && !(c == '\t' || c == '\r' || c == '\n')) {
      Glyph glyph = Glyph();
      TTF_GetGlyphMetrics(app.glyphAtlas.ttf, cast(uint)(c), &glyph.mmX[0], &glyph.mmX[1], &glyph.mmY[0], &glyph.mmY[1], &glyph.advance);
      auto gs = TTF_RenderGlyph_Blended(app.glyphAtlas.ttf, cast(uint)(c), SDL_Color(0, 0, 0, 0));
        SDL_SetSurfaceBlendMode(gs, SDL_BLENDMODE_NONE);
      if (atlasloc + gs.w >= app.glyphAtlas.width) { i = atlasloc = 0; penY += rowMaxH; rowMaxH = 0; }
      if (penY + gs.h > app.glyphAtlas.height) {
        SDL_DestroySurface(gs);
        SDL_Log("WARNING: GlyphAtlas overflow at (and after) character %d", c);
        break;
      }
      if (gs.h > rowMaxH) rowMaxH = gs.h;
      if (app.glyphAtlas.advance < glyph.advance) app.glyphAtlas.advance = glyph.advance;
      if (app.glyphAtlas.miny > glyph.mmY[0]) app.glyphAtlas.miny = glyph.mmY[0];
      glyph.aDim = [atlasloc, penY];
      glyph.sDim = [gs.w, gs.h];
      app.glyphAtlas.glyphs[c] = glyph;
      app.glyphAtlas.atlas ~= c;
      SDL_Rect dst = { atlasloc, penY, gs.w, gs.h };
      SDL_BlitSurface(gs, null, app.glyphAtlas.surface, &dst);
      atlasloc += gs.w;
      SDL_DestroySurface(gs);
      i++;
    }
    c++;
  }
  auto time = (MonoTime.currTime - sT).total!"msecs"();
  if (app.verbose) {
    SDL_Log("%d unicode glyphs (%d unique ones)", app.glyphAtlas.atlas.length, app.glyphAtlas.glyphs.length);
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