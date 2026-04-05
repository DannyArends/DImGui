/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : beginSingleTimeCommands, endSingleTimeCommands;
import textures : toRGBA, toGPU;
import images : createImage, deAllocate, imageSize;
import swapchain : createImageView;

/** Glyph stores SDL2_TTF glyph data
 */
struct Glyph {
  int minx;
  int maxx;
  int miny;
  int maxy;
  int advance;
  int atlasloc;
  int atlasrow;

  @property @nogc int gX() nothrow { return(advance - minx); }
  @property @nogc int gY() nothrow { return(maxy - miny); }
}

/** The GlyphAtlas structure holds links to the TTF_Font, Glyphs, Texture and the atlas
 */
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
  @property float tX(Glyph glyph) { 
    return(glyph.atlasloc / cast(float)(texture.width));
  }

  /** Glyph texture Y postion */
  @property float tY(Glyph glyph) {
    return((this.lineHeight * glyph.atlasrow) / cast(float)(texture.height));
  }

  /** X postion of the glyph, when on column col */
  @property float pX(Glyph glyph, size_t col) {
    return(cast(float)(col) * glyph.advance + glyph.minx);
  }

  /** Y postion of the glyph, when on line[0] out of line[1] */
  @property float pY(Glyph glyph, size_t[2] line) {
    return(cast(float)(line[1] - line[0]) * this.lineHeight + glyph.miny - this.miny);
  }

  alias texture this;
}

/** Loads a GlyphAtlas from file */
void loadGlyphAtlas(ref App app, string filename = "data/fonts/FreeMono.ttf", ubyte pointsize = 40, dchar to = '\U000000FF', uint dim = 1024) {
  version(Android){ }else{ filename = format("app/src/main/assets/%s", fromStringz(filename)); }
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

  TTF_SetFontSDF(app.glyphAtlas.ttf, false);
  app.glyphAtlas.texture = Texture(app.glyphAtlas.path, dim, dim, SDL_CreateSurface(dim, dim, SDL_PIXELFORMAT_RGBA32));
  SDL_SetSurfaceBlendMode(app.glyphAtlas.surface, SDL_BLENDMODE_NONE);
  app.glyphAtlas.width = app.glyphAtlas.height = dim;

  uint i, atlasrow, atlasloc = 0;
  app.glyphAtlas.atlas = [];
  dchar c = '\U00000000';
  while (c <= to) {
    if (isValidDchar(c) && TTF_FontHasGlyph(app.glyphAtlas.ttf, cast(uint)(c)) && !(c == '\t' || c == '\r' || c == '\n')) {
      Glyph glyph = Glyph();
      TTF_GetGlyphMetrics(app.glyphAtlas.ttf, cast(uint)(c), &glyph.minx, &glyph.maxx, &glyph.miny, &glyph.maxy, &glyph.advance);
      auto gs = TTF_RenderGlyph_Blended(app.glyphAtlas.ttf, cast(uint)(c), SDL_Color(255, 255, 255, 255));
      if (!gs) { c++; continue; }
      if (atlasloc + gs.w >= app.glyphAtlas.width) { i = atlasloc = 0; atlasrow++; }
      if (app.glyphAtlas.advance < glyph.advance) app.glyphAtlas.advance = glyph.advance;
      if (app.glyphAtlas.miny > glyph.miny) app.glyphAtlas.miny = glyph.miny;
      glyph.atlasloc = atlasloc;
      glyph.atlasrow = atlasrow;
      app.glyphAtlas.glyphs[c] = glyph;
      app.glyphAtlas.atlas ~= c;
      SDL_Rect dst = { atlasloc, atlasrow * app.glyphAtlas.lineHeight, gs.w, gs.h };
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
  SDL_Log("%d/%d Glyphs on %d lines [%d x %d] in %d msecs\n", app.glyphAtlas.glyphs.length, c, ++atlasrow, dim, dim, time);
}

/** Create a TextureImage layout and view from the SDL_Surface and adds it to the App.textureArray */
void uploadFont(ref App app) {
  if(app.verbose) SDL_Log("Uploading Font Texture to GPU");
  auto commandBuffer = app.beginSingleTimeCommands(app.transferPool);
  app.toGPU(commandBuffer, app.glyphAtlas.texture);
  app.endSingleTimeCommands(commandBuffer, app.transfer);
  app.textures ~= app.glyphAtlas.texture;
  app.mainDeletionQueue.add((){ app.deAllocate(app.glyphAtlas.texture); });
}
