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
    return((glyph.atlasloc + glyph.minx) / cast(float)(texture.width));
  }

  /** Glyph texture Y postion */
  @property  float tY(Glyph glyph) {
    int lineHsum = this.lineHeight * glyph.atlasrow;
    return((lineHsum + (this.ascent - glyph.maxy)) / cast(float)(texture.height));
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
void loadGlyphAtlas(ref App app, string filename = "data/fonts/FreeMono.ttf", ubyte pointsize = 80, dchar to = '\U000000FF', uint width = 1024) {
  version(Android){ }else{ filename = format("app/src/main/assets/%s", fromStringz(filename)); }
  SDL_Log("loadGlyphAtlas: %s", toStringz(filename));
  GlyphAtlas glyphatlas = GlyphAtlas(filename);
  glyphatlas.pointsize = (pointsize == 0)? 12 : pointsize;
  glyphatlas.ttf = TTF_OpenFont(toStringz(filename), cast(float)glyphatlas.pointsize);
  if (!glyphatlas.ttf) {
    SDL_Log("Error by loading TTF_Font %s: %s\n", toStringz(filename), SDL_GetError());
    abort();
  }
  glyphatlas.width = width;
  glyphatlas.atlas = glyphatlas.createGlyphAtlas(to, app.verbose > 0);
  app.glyphAtlas = glyphatlas;
}

/** Populates the GlyphAtlas with Glyphs to dchar in our atlas */
string createGlyphAtlas(ref GlyphAtlas glyphatlas, dchar to = '\U000000FF', bool verbose = true) {
  if(verbose) SDL_Log("createGlyphAtlas");
  MonoTime sT = MonoTime.currTime;
  int i, atlasrow, atlasloc;
  string atlas = [];
  dchar c = '\U00000000';
  while (c <= to) {
    if (isValidDchar(c) && TTF_FontHasGlyph(glyphatlas.ttf, cast(uint)(c)) && !(c == '\t' || c == '\r' || c == '\n')) {
      Glyph glyph = Glyph();
      TTF_GetGlyphMetrics(glyphatlas.ttf, cast(uint)(c), &glyph.minx, &glyph.maxx, &glyph.miny, &glyph.maxy, &glyph.advance);
      if (atlasloc + glyph.advance >= glyphatlas.width) {
        atlas ~= '\n';
        i = 0;
        atlasloc = 0;
        atlasrow++;
      }
      if (glyphatlas.advance < glyph.advance) glyphatlas.advance = glyph.advance;
      if (glyphatlas.miny > glyph.miny) glyphatlas.miny = glyph.miny;
      glyph.atlasloc = atlasloc;
      glyph.atlasrow = atlasrow;
      glyphatlas.glyphs[c] = glyph;
      atlas ~= c;
      atlasloc += glyph.advance;
      i++;
    }
    c++;
  }
  glyphatlas.pointsize = glyphatlas.pointsize;
  glyphatlas.ascent = TTF_GetFontAscent(glyphatlas.ttf);
  glyphatlas.lineHeight = TTF_GetFontHeight(glyphatlas.ttf);
  glyphatlas.height = (atlasrow + 1) * glyphatlas.lineHeight;

  auto time = (MonoTime.currTime - sT).total!"msecs"();  // Update the current time
  if (verbose) {
    SDL_Log("%d/%d Glyphs on %d lines [%d x %d] in %d msecs\n", glyphatlas.glyphs.length, c, ++atlasrow, glyphatlas.width, glyphatlas.height, time);
    SDL_Log("%d unicode glyphs (%d unique ones)", atlas.length, glyphatlas.glyphs.length);
    SDL_Log("FontAscent: %d, FontAdvance: %d", glyphatlas.ascent, glyphatlas.advance);
  }
  return(atlas);
}

/** Create a TextureImage layout and view from the SDL_Surface and adds it to the App.textureArray */
void createFontTexture(ref App app) {
  TTF_SetFontSDF(app.glyphAtlas.ttf, false);
  auto s = SDL_CreateSurface(app.glyphAtlas.width, app.glyphAtlas.height, SDL_PIXELFORMAT_RGBA32);
  SDL_SetSurfaceBlendMode(s, SDL_BLENDMODE_NONE);

  foreach(c, ref glyph; app.glyphAtlas.glyphs) {
    auto glyphSurface = TTF_RenderGlyph_Blended(app.glyphAtlas.ttf, cast(uint)c, SDL_Color(255, 255, 255, 255));
    if(!glyphSurface) continue;
    int dstX = glyph.atlasloc + glyph.minx;
    int dstY = app.glyphAtlas.lineHeight * glyph.atlasrow + (app.glyphAtlas.ascent - glyph.maxy);
    SDL_Rect dst = { dstX, dstY, glyphSurface.w, glyphSurface.h };
    SDL_BlitSurface(glyphSurface, null, s, &dst);
    SDL_DestroySurface(glyphSurface);
  }

  if(app.verbose) SDL_Log("createTextureImage: Surface obtained: %p [%dx%d:%d]", s, s.w, s.h, SDL_GetPixelFormatDetails(s.format).bytes_per_pixel);
  if(SDL_GetPixelFormatDetails(s.format).bytes_per_pixel != 4) s.toRGBA();

  app.glyphAtlas.texture = Texture(app.glyphAtlas.path, s.w, s.h, s);
  if(app.verbose) SDL_Log("Uploading Font Texture to GPU");
  auto commandBuffer = app.beginSingleTimeCommands(app.transferPool);
  app.toGPU(commandBuffer, app.glyphAtlas.texture);
  app.endSingleTimeCommands(commandBuffer, app.transfer);
  app.textures ~= app.glyphAtlas.texture;
  app.mainDeletionQueue.add((){ app.deAllocate(app.glyphAtlas.texture); });
}
