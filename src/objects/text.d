import engine;

import geometry : opacity;
import matrix : translate, translateScale, multiply, rotate;

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

/** All floating 3D world text: the shared geometry plus per-entry bookkeeping (original string + instance
 * range) so an entry can be looked up, moved, or removed later by its index. */
struct WorldText {
  Text text;                      /// The single shared instanced Text geometry
  string[] texts;                 /// Original string per placed entry
  size_t[2][] ranges;             /// [start, count) instance range per placed entry, parallel to texts
}

/** Ensure the single shared world-text object exists */
void ensureWorldText(ref App app) {
  if(app.worldText.text !is null) return;
  app.worldText.text = new Text(app);
  app.objects ~= app.worldText.text;
}

/** Compute the per-glyph DrawInstances for a (possibly multi-line) string, laid out at pos/rot/scale */
private DrawInstance[] layoutText(ref App app, string value, float[3] pos, float scale, float[4] color, float[3] rot) {
  auto atlas = app.glyphAtlas;
  float glyphscale = (1.0f/scale) * atlas.pointsize;
  size_t[2] line = [1, value.split("\n").length];
  uint col = 0;
  Matrix labelTransform = translate(pos).multiply(rotate(rot));
  DrawInstance[] insts;
  foreach(dchar c; value.array) {
    if(c == '\n'){ line[0]++; col = 0; continue; }
    if(c == ' ') { col++; continue; }
    auto g = atlas.getGlyph(c);
    float pX = atlas.pX(g, col) / glyphscale;
    float pY = atlas.pY(g, line) / glyphscale;
    float w = atlas.qW(g, glyphscale);
    float h = atlas.qH(g, glyphscale);
    Matrix m = labelTransform.multiply(translateScale([pX, pY, 0.0f], [w, h, 1.0f]));
    float[4] uv = [atlas.tX(g), atlas.tY(g) + atlas.tYo(g), atlas.tXo(g), -atlas.tYo(g)];
    insts ~= DrawInstance(m, uv, color);
    col++;
  }
  return insts;
}

/** Place a (possibly multi-line) piece of world text. Returns its index into app.worldText.texts/ranges,
 * so callers can look it up later to move or remove it. All world text shares one draw call. */
size_t addWorldText(ref App app, string value, float[3] pos, float[3] rot, float scale = 1.0f, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]) {
  app.ensureWorldText();
  auto range = app.worldText.text.addInstances(app.layoutText(value, pos, scale, color, rot));
  app.worldText.text.syncInstances();
  app.worldText.texts ~= value;
  app.worldText.ranges ~= range;
  return app.worldText.texts.length - 1;
}
