import engine;

import geometry : opacity;
import matrix : translate, translateScale, multiply;

/** Shared instanced text: one unit quad mesh, reused by every glyph of every label via per-instance
 * transform + UV remap. All labels share this one object, so all label text draws in a single draw call. */
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

/** Ensure the single shared label/text object exists */
void ensureLabels(ref App app) {
  if(app.labels !is null) return;
  app.labels = new Text(app);
  app.objects ~= app.labels;
}

/** Place a (possibly multi-line) label floating at a world position. Returns the [start, count) range
 * of instances it occupies in the shared Text object, so callers can move (overwrite in place + syncInstances)
 * or later remove it. All labels share one draw call regardless of how many are placed. */
size_t[2] addLabel(ref App app, string value, float[3] pos, float scale = 1.0f, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]) {
  app.ensureLabels();
  auto atlas = app.glyphAtlas;
  float glyphscale = (1.0f/scale) * atlas.pointsize;
  size_t[2] line = [1, value.split("\n").length];
  uint col = 0;
  DrawInstance[] insts;
  foreach(dchar c; value.array) {
    if(c == '\n'){ line[0]++; col = 0; continue; }
    if(c == ' ') { col++; continue; }
    auto g = atlas.getGlyph(c);
    float pX = atlas.pX(g, col) / glyphscale;
    float pY = atlas.pY(g, line) / glyphscale;
    float w = atlas.qW(g, glyphscale);
    float h = atlas.qH(g, glyphscale);
    Matrix m = translate(pos).multiply(translateScale([pX, pY, 0.0f], [w, h, 1.0f]));
    float[4] uv = [atlas.tX(g), atlas.tY(g) + atlas.tYo(g), atlas.tXo(g), -atlas.tYo(g)];
    insts ~= DrawInstance(m, uv, color);
    col++;
  }
  auto range = app.labels.addInstances(insts);
  app.labels.syncInstances();
  return range;
}
