/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : opacity;
import matrix : translate, translateScale, multiply, rotate;
import vector : vSub;

/** Shared instanced text: one unit quad mesh, reused by every glyph via per-instance transform + UV remap.
 * All world text shares this one object, so it all draws in a single draw call. */
class Text : Geometry {
  this(ref App app) {
    vertices ~= [ Vertex([0.0f, 0.0f, 0.0f], [0.0f, 0.0f], [1.0f, 1.0f, 1.0f, 1.0f]),
                  Vertex([1.0f, 0.0f, 0.0f], [1.0f, 0.0f], [1.0f, 1.0f, 1.0f, 1.0f]),
                  Vertex([1.0f, 1.0f, 0.0f], [1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]),
                  Vertex([0.0f, 1.0f, 0.0f], [0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]) ];
    indices ~= [0, 2, 1, 0, 3, 2];
    meshes["Text"] = Mesh([0, cast(uint)vertices.length]);
    this.opacity(app.glyphAtlas.path);
    isOpaque = false;
    castShadow = false;
    geometry = (){ return(typeof(this).stringof); };
  }
}

struct TextInfo {
  string data;
  float[3] pos = [0.0f, 0.0f, 0.0f];
  float[3] rot = [0.0f, 0.0f, 0.0f];
  float scale = 1.0f;
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];
  size_t[2] range;
  alias data this;
}

/** All floating 3D world text */
struct WorldText {
  Text text;                        /// The single shared instanced Text geometry
  TextInfo[] texts;                 /// One self-contained record per placed entry
}

/** Ensure the single shared world-text object exists */
void ensureWorldText(ref App app) {
  if(app.worldText.text !is null) return;
  app.worldText.text = new Text(app);
  app.objects ~= app.worldText.text;
}

/** Compute the per-glyph DrawInstances for a TextInfo entry (its own pos/rot/scale/color) */
private DrawInstance[] layoutText(ref App app, TextInfo info) {
  auto atlas = app.glyphAtlas;
  float glyphscale = (1.0f/info.scale) * atlas.pointsize;
  size_t[2] line = [1, info.data.split("\n").length];
  uint col = 0;
  Matrix labelTransform = translate(info.pos).multiply(rotate(info.rot));
  DrawInstance[] insts;
  foreach(dchar c; info.data.array) {
    if(c == '\n'){ line[0]++; col = 0; continue; }
    if(c == ' ') { col++; continue; }
    auto g = atlas.getGlyph(c);
    float pX = atlas.pX(g, col) / glyphscale;
    float pY = atlas.pY(g, line) / glyphscale;
    float w = atlas.qW(g, glyphscale);
    float h = atlas.qH(g, glyphscale);
    Matrix m = labelTransform.multiply(translateScale([pX, pY, 0.0f], [w, h, 1.0f]));
    float[4] uv = [atlas.tX(g), atlas.tY(g) + atlas.tYo(g), atlas.tXo(g), -atlas.tYo(g)];
    insts ~= DrawInstance(m, uv, info.color);
    col++;
  }
  return insts;
}

/** Place a (possibly multi-line) piece of world text. */
size_t addWorldText(ref App app, string value, float[3] pos, float[3] rot, float scale = 1.0f, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]) {
  app.ensureWorldText();
  auto info = TextInfo(value, pos, rot, scale, color);
  info.range = app.worldText.text.addInstances(app.layoutText(info));
  app.worldText.text.syncInstances();
  app.worldText.texts ~= info;
  return app.worldText.texts.length - 1;
}

/** Move a piece of world text to a new position, keeping its rotation/scale/local glyph layout intact. */
void moveWorldText(ref App app, size_t i, float[3] pos) {
  if(i >= app.worldText.texts.length) return;
  float[3] delta = pos.vSub(app.worldText.texts[i].pos);
  auto range = app.worldText.texts[i].range;
  foreach(ref inst; app.worldText.text.instances[range[0] .. range[0]+range[1]]) {
    inst.matrix = translate(delta).multiply(inst.matrix);
  }
  app.worldText.texts[i].pos = pos;
  app.worldText.text.syncInstances();
}

/** Remove a piece of world text placed via addWorldText */
size_t removeWorldText(ref App app, size_t i) {
  if(i >= app.worldText.texts.length) return size_t.max;
  size_t start = app.worldText.texts[i].range[0];
  size_t count = app.worldText.texts[i].range[1];

  // Cut the freed range out of the shared instance buffer, and shift every other entry's start down to match
  app.worldText.text.instances = app.worldText.text.instances[0 .. start] ~ app.worldText.text.instances[start+count .. $];
  foreach(ref t; app.worldText.texts) { if(t.range[0] > start) t.range[0] -= count; }
  app.worldText.text.syncInstances();

  // Swap-remove the entry itself, same trick as removeLight — only the last index (if moved) changes identity
  size_t last = app.worldText.texts.length - 1;
  if(i != last) { app.worldText.texts[i] = app.worldText.texts[last]; }
  app.worldText.texts.length = last;
  return (i != last) ? last : size_t.max;
}
