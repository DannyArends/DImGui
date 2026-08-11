/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : opacity;
import material : ensureMaterial;
import matrix : degree, translate, translateScale, multiply, rotate;
import textures : mapTextures;
import vector : vSub, vMul;

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
    initInstanced("Text");
    this.opacity(app.glyphAtlas.path);
    isOpaque = false;
    castShadow = false;
    mName = typeof(this).stringof;
  }
}

struct TextInfo {
  string data;
  float[3] pos = [0.0f, 0.0f, 0.0f];
  float[3] rot = [0.0f, 0.0f, 0.0f];
  float scale = 1.0f;
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];
  size_t[2] range;
  bool billboard = false;
  alias data this;
  
  @property @nogc size_t start() nothrow { return(range[0]); }
  @property @nogc size_t count() nothrow { return(range[1]); }
  @property @nogc size_t to() nothrow { return(range[0] + range[1]); }
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
  app.ensureMaterial(app.objects[($-1)]);
  app.mapTextures(app.objects[($-1)]);
}

/** Compute the per-glyph DrawInstances for a TextInfo entry (its own pos/rot/scale/color) */
private DrawInstance[] layoutText(ref App app, TextInfo info) {
  auto atlas = app.glyphAtlas;
  float glyphscale = (1.0f/info.scale) * atlas.pointsize;
  auto lines = info.data.split("\n");

  // Real per-line pixel width: sum of each character's own advance, not an assumed uniform width
  float[] lineWidths = new float[lines.length];
  foreach(li, ln; lines) {
    float w = 0;
    foreach(dchar lc; ln.array) { w += (lc == ' ') ? atlas.advance : atlas.getGlyph(lc).advance; }
    lineWidths[li] = w / glyphscale;
  }

  size_t[2] line = [1, lines.length];
  float penX = 0;
  Matrix labelTransform = translate(info.pos).multiply(rotate(info.rot));
  DrawInstance[] insts;
  foreach(dchar c; info.data.array) {
    if(c == '\n'){ line[0]++; penX = 0; continue; }
    if(c == ' ') { penX += atlas.advance; continue; }
    auto g = atlas.getGlyph(c);
    float pX = (penX + g.bearing[0]) / glyphscale - lineWidths[line[0]-1] * 0.5f;
    float pY = atlas.pY(g, line) / glyphscale;
    float w = atlas.qW(g, glyphscale);
    float h = atlas.qH(g, glyphscale);
    Matrix m = labelTransform.multiply(translateScale([pX, pY, 0.0f], [w, h, 1.0f]));
    float[4] uv = [atlas.tX(g), atlas.tY(g) + atlas.tYo(g), atlas.tXo(g), -atlas.tYo(g)];
    insts ~= DrawInstance(m, 0, info.color, uv);
    penX += g.advance;
  }
  return insts;
}

/** Place a (possibly multi-line) piece of world text. */
size_t addWorldText(ref App app, string value, float[3] pos, float[3] rot, float scale = 1.0f, 
                    float[4] color = [1.0f, 1.0f, 1.0f, 1.0f], bool billboard = false) {
  app.ensureWorldText();
  auto info = TextInfo(value, pos, rot, scale, color);
  info.billboard = billboard;
  info.range = app.worldText.text.addInstances(app.layoutText(info));
  app.worldText.text.syncInstances();
  app.worldText.texts ~= info;
  return app.worldText.texts.length - 1;
}

/** Move a piece of world text to a new position, keeping its rotation/scale/local glyph layout intact. */
void moveWorldText(ref App app, size_t i, float[3] pos) {
  if(i >= app.worldText.texts.length) return;
  float[3] delta = pos.vSub(app.worldText.texts[i].pos);
  auto info = app.worldText.texts[i];
  foreach(ref inst; app.worldText.text.instances[info.start() .. info.to()]) {
    inst.matrix = translate(delta).multiply(inst.matrix);
  }
  app.worldText.texts[i].pos = pos;
  app.worldText.text.syncInstances();
}

/** Remove a piece of world text placed via addWorldText */
size_t removeWorldText(ref App app, size_t i) {
  if(i >= app.worldText.texts.length) return size_t.max;
  auto info = app.worldText.texts[i];

  // Cut the freed range out of the shared instance buffer, and shift every other entry's start down to match
  app.worldText.text.instances = app.worldText.text.instances[0 .. info.start] ~ app.worldText.text.instances[info.to .. $];
  foreach(ref t; app.worldText.texts) { if(t.range[0] > info.start) t.range[0] -= info.count; }
  app.worldText.text.syncInstances();

  return app.worldText.texts.removeAt(i);
}

/** Re-lay-out every billboarded piece of world text so it yaws to face the current camera. */
void updateWorldTextBillboards(ref App app) {
  bool any = false;
  foreach(ref info; app.worldText.texts) {
    if(!info.billboard) continue;
    float[3] dir = app.camera.position.vSub(info.pos);
    float newYaw = -degree(atan2(dir[0], dir[2]));
    float deltaYaw = newYaw - info.rot[0];
    if(deltaYaw == 0.0f) continue;
    Matrix pivot = translate(info.pos).multiply(rotate([deltaYaw, 0.0f, 0.0f])).multiply(translate(info.pos.vMul(-1.0f)));
    foreach(ref inst; app.worldText.text.instances[info.start .. info.to]) {
      inst.matrix = pivot.multiply(inst.matrix);
    }
    info.rot[0] = newYaw;
    any = true;
  }
  if(any) app.worldText.text.syncInstances();
}
