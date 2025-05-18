/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.array : split, array;
import vertex : Vertex;
import geometry : Instance, Geometry, texture;
import glyphatlas : GlyphAtlas;

class Text : Geometry {
  this(App app, string value = "Hellow World", float scale = 1.0f, bool verbose = false){
    auto atlas = app.glyphAtlas;
    float glyphscale = (1.0f/scale) * atlas.pointsize;
    if(verbose) SDL_Log("GlyphAtlas: %d, %d, %d, %d, %d", atlas.width, atlas.height, atlas.ascent, atlas.miny, atlas.advance);
    size_t[2] line = [1, value.split("\n").length];
    uint col = 0;
    uint nGlyhs = 0;
    foreach(i, dchar c; value.array) {
      if(c == '\n'){ line[0]++; col = 0; continue; }
      auto cChar = atlas.getGlyph(c);

      // Convert everything to Glyphscale (based on the chosen fontsize)
      float pX = atlas.pX(cChar, col) /  glyphscale;
      float pY = atlas.pY(cChar, line) /  glyphscale;
      float w = cChar.gX / glyphscale;
      float h = cChar.gY / glyphscale;
      float tXo = cChar.gX / cast(float)(atlas.width);
      float tYo = cChar.gY / cast(float)(atlas.height);

      vertices ~=
               [ Vertex([   pX,   pY, 0.0f], [atlas.tX(cChar), atlas.tY(cChar)+ tYo], [1.0f, 1.0f, 1.0f, 1.0f]), 
                 Vertex([ w+pX,   pY, 0.0f], [atlas.tX(cChar)+ tXo, atlas.tY(cChar)+ tYo], [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([ w+pX, h+pY, 0.0f], [atlas.tX(cChar)+ tXo, atlas.tY(cChar)], [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([   pX, h+pY, 0.0f], [atlas.tX(cChar), atlas.tY(cChar)], [1.0f, 1.0f, 1.0f, 1.0f])
               ];

      indices ~= [(nGlyhs*4)+0, (nGlyhs*4)+2, (nGlyhs*4)+1, (nGlyhs*4)+0, (nGlyhs*4)+3, (nGlyhs*4)+2];
      col++;
      nGlyhs++;
    }
    instances = [Instance()];
    this.texture(app.textures, app.glyphAtlas.path);
    name = (){ return(typeof(this).stringof); };
  }
}

