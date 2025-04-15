// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html
import engine;

import std.datetime : MonoTime;
import std.utf : isValidDchar;
import std.string : toStringz;
import glyph: Glyph; 
import textures : Texture, toRGBA;
import images : createImage, imageSize, transitionImageLayout;
import buffer : copyBufferToImage, createBuffer;
import swapchain : createImageView;
/* 
  The GlyphAtlas structure holds links to the TTF_Font, Glyphs, Texture and the atlas
*/
struct GlyphAtlas {
  const(char)* path;
  TTF_Font* ttf; // Pointer to the loaded TTF_Font
  ubyte pointsize; // Font size
  Glyph[dchar] glyphs; // associative array couples Glyph and dchar
  ushort[] atlas; // ushort array of chars which were valid and stored into the atlas (\n for linebreaks)
  Texture texture; // Holds the SDL surface with the atlas
  int width;
  int height;
  int ascent;
  int miny;
  int advance;
  SDL_Surface* _surface = null;

  // Get a specific glyph from the atlas
  Glyph getGlyph(dchar letter) nothrow {
    if(letter in glyphs) return(glyphs[letter]);
    return(glyphs[0]);
  }

  // Glyph texture X postion
  @property float tX(Glyph glyph) { 
    return((glyph.atlasloc + glyph.minx) / cast(float)(surface.w));
  }

  // Glyph texture Y postion
  @property  float tY(Glyph glyph) {
    int lineHsum = (this.height) * glyph.atlasrow;
    return((lineHsum + (this.ascent - glyph.maxy)) / cast(float)(surface.h));
  }

  // X postion of the glyph, when on column col
  @property float pX(Glyph glyph, size_t col) {
    return(cast(float)(col) * glyph.advance + glyph.minx);
  }

  // Y postion of the glyph, when on line[0] out of line[1]
  @property float pY(Glyph glyph, size_t[2] line) {
    return(cast(float)(line[1] - line[0]) * (this.height) + glyph.miny - this.miny);
  }

  // Generate a surface from the initialized atlas
  // NOTE: Make sure ttf, atlas, and width have been set by calling createGlyphAtlas()
  SDL_Surface* surface() {
    if(_surface == null) _surface = TTF_RenderUNICODE_Blended_Wrapped(ttf, &atlas[0], SDL_Color(255, 255, 255, 255), width);
    return(_surface);
  };
  alias surface this;
}

// Loads a GlyphAtlas from file
void loadGlyphAtlas(ref App app, const(char)* filename, ubyte pointsize = 12, dchar to = '\U00000FFF', uint width = 1024, uint max_width = 1024) {
  GlyphAtlas glyphatlas = GlyphAtlas(filename);
  glyphatlas.pointsize = (pointsize == 0)? 12 : pointsize;
  glyphatlas.ttf = TTF_OpenFont(filename, glyphatlas.pointsize);
  if (!glyphatlas.ttf) {
    SDL_Log("Error by loading TTF_Font %s: %s\n", filename, SDL_GetError());
    assert(0, "Unable to load font");
  }
  glyphatlas.atlas = glyphatlas.createGlyphAtlas(to, width, max_width);
  app.glyphAtlas = glyphatlas;
}

// Populates the GlyphAtlas with Glyphs to dchar in our atlas
ushort[] createGlyphAtlas(ref GlyphAtlas glyphatlas, dchar to = '\U00000FFF', uint width = 1024, uint max_width = 1024) {
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
  glyphatlas.height = glyphatlas.pointsize;
  glyphatlas.ascent = TTF_FontAscent(glyphatlas.ttf);

  MonoTime cT = MonoTime.currTime;
  auto time = (cT - sT).total!"msecs"();  // Update the current time
  SDL_Log("%d/%d Glyphs on %d lines [%d x %d] in %d msecs\n", glyphatlas.glyphs.length, c, ++atlasrow, glyphatlas.width, glyphatlas.height, time);
  return(atlas);
}

// Create a TextureImage layout and view from the SDL_Surface and adds it to the App.textureArray
void createFontTexture(ref App app, SDL_Surface* surface, const(char)* path = "DEFAULT") {
  SDL_Log("createTextureImage: Surface obtained: %p [%dx%d:%d]", surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
  if (surface.format.BitsPerPixel != 32) surface.toRGBA();

  Texture texture = { width: surface.w, height: surface.h, surface: surface };
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;
  app.createBuffer(&stagingBuffer, &stagingBufferMemory, surface.imageSize, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, 
    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
  );
  void* data;
  vkMapMemory(app.device, stagingBufferMemory, 0, surface.imageSize, 0, &data);
  memcpy(data, surface.pixels, cast(uint)surface.imageSize);
  vkUnmapMemory(app.device, stagingBufferMemory);
  app.createImage(surface.w, surface.h,&texture.textureImage, &texture.textureImageMemory, VK_FORMAT_R8G8B8A8_SRGB, VK_IMAGE_TILING_OPTIMAL, 
    VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
  );

  app.transitionImageLayout(texture.textureImage, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
  app.copyBufferToImage(stagingBuffer, texture.textureImage, surface.w, surface.h);
  app.transitionImageLayout(texture.textureImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  texture.textureImageView = app.createImageView(texture.textureImage, VK_FORMAT_R8G8B8A8_SRGB);

  SDL_Log("Freeing surface: %p [%dx%d:%d]", surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
  SDL_FreeSurface(surface);
  vkDestroyBuffer(app.device, stagingBuffer, null);
  vkFreeMemory(app.device, stagingBufferMemory, null);
  app.textures ~= texture;
}

