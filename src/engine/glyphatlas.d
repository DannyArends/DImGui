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
  Glyph[dchar] glyphs;  /// Associative array couples Glyph and dchar
  ushort[] atlas;       /// ushort array of chars which were valid and stored into the atlas (\n for linebreaks)
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
    int lineHsum = (this.pointsize) * glyph.atlasrow;
    return((lineHsum + (this.ascent - glyph.maxy)) / cast(float)(texture.height));
  }

  /** X postion of the glyph, when on column col */
  @property float pX(Glyph glyph, size_t col) {
    return(cast(float)(col) * glyph.advance + glyph.minx);
  }

  /** Y postion of the glyph, when on line[0] out of line[1] */
  @property float pY(Glyph glyph, size_t[2] line) {
    return(cast(float)(line[1] - line[0]) * (this.pointsize) + glyph.miny - this.miny);
  }

  alias texture this;
}

/** Loads a GlyphAtlas from file */
void loadGlyphAtlas(ref App app, 
                    string filename = "data/fonts/FreeMono.ttf", 
                    ubyte pointsize = 80, dchar to = '\U000000FF', uint width = 1024, uint max_width = 1024) {
  version(Android){ }else{
    filename = format("app/src/main/assets/%s", fromStringz(filename));
  }
  SDL_Log("loadGlyphAtlas: %s", toStringz(filename));
  GlyphAtlas glyphatlas = GlyphAtlas(filename);
  glyphatlas.pointsize = (pointsize == 0)? 12 : pointsize;
  glyphatlas.ttf = TTF_OpenFont(toStringz(filename), glyphatlas.pointsize);
  if (!glyphatlas.ttf) {
    SDL_Log("Error by loading TTF_Font %s: %s\n", toStringz(filename), SDL_GetError());
    abort();
  }
  glyphatlas.atlas = glyphatlas.createGlyphAtlas(to, width, max_width);
  app.glyphAtlas = glyphatlas;
}

/** Populates the GlyphAtlas with Glyphs to dchar in our atlas */
ushort[] createGlyphAtlas(ref GlyphAtlas glyphatlas, dchar to = '\U000000FF', uint width = 1024, uint max_width = 1024, bool verbose = true) {
  SDL_Log("createGlyphAtlas");
  MonoTime sT = MonoTime.currTime;
  int i, atlasrow, atlasloc;
  ushort[] atlas = [];
  dchar c = '\U00000000';
  glyphatlas.width = (width > max_width)? max_width : width;
  while (c <= to) {
    if (isValidDchar(c) && TTF_GlyphIsProvided(glyphatlas.ttf, cast(ushort)(c)) && !(c == '\t' || c == '\r' || c == '\n')) {
      Glyph glyph = Glyph();
      TTF_GlyphMetrics(glyphatlas.ttf, cast(ushort)(c), &glyph.minx, &glyph.maxx, &glyph.miny, &glyph.maxy, &glyph.advance);
      if (atlasloc + glyph.advance >= glyphatlas.width) {
        atlas ~= cast(ushort)('\n');
        i = 0;
        atlasloc = 0;
        atlasrow++;
      }
      if (glyphatlas.advance < glyph.advance) glyphatlas.advance = glyph.advance;
      if (glyphatlas.miny > glyph.miny) glyphatlas.miny = glyph.miny;
      glyph.atlasloc = atlasloc;
      glyph.atlasrow = atlasrow;
      glyphatlas.glyphs[c] = glyph;
      atlas ~= cast(ushort)(c);
      atlasloc += glyph.advance;
      i++;
    }
    c++;
  }
  SDL_Log("%d unicode glyphs (%d unique ones)\n", atlas.length, glyphatlas.glyphs.length);
  SDL_Log("FontAscent: %d\n", TTF_FontAscent(glyphatlas.ttf));
  SDL_Log("FontAdvance: %d\n", glyphatlas.advance);
  glyphatlas.pointsize = glyphatlas.pointsize;
  glyphatlas.ascent = TTF_FontAscent(glyphatlas.ttf);

  auto time = (MonoTime.currTime - sT).total!"msecs"();  // Update the current time
  if(verbose) {
    SDL_Log("%d/%d Glyphs on %d lines [%d x %d] in %d msecs\n", glyphatlas.glyphs.length, c, ++atlasrow, glyphatlas.width, glyphatlas.height, time);
  }
  return(atlas);
}

/** Create a TextureImage layout and view from the SDL_Surface and adds it to the App.textureArray */
void createFontTexture(ref App app) {
  if(app.verbose) SDL_Log("createFontTexture");
  auto surface = TTF_RenderUNICODE_Blended_Wrapped(app.glyphAtlas.ttf, &app.glyphAtlas.atlas[0], SDL_Color(255, 255, 255, 255), app.glyphAtlas.width);
  if(app.verbose) SDL_Log("createTextureImage: Surface obtained: %p [%dx%d:%d]", surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
  if(surface.format.BitsPerPixel != 32) surface.toRGBA();

  app.glyphAtlas.texture = Texture(app.glyphAtlas.path, surface.w, surface.h, surface);
  SDL_Log("Adding Font Texture");
  auto commandBuffer = app.beginSingleTimeCommands(app.transferPool);
  app.toGPU(commandBuffer, app.glyphAtlas.texture);
  app.endSingleTimeCommands(commandBuffer, app.transfer);
  app.textures ~= app.glyphAtlas.texture;
  SDL_Log("Added Font Texture");
  app.mainDeletionQueue.add((){ app.deAllocate(app.glyphAtlas.texture); });
}
