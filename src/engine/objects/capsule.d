/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : paletteOrdinal;
import cone : computeThetas;
import cylinder : computeWall;
import vector : x, y, z, normalize;

/** Capsule: a cylinder of 'height' capped by two hemispheres of 'radius' (total height = height + 2*radius). */
class Capsule : Geometry {
  this(float radius = 0.5f, float height = 1.0f, uint numSegments = 32, uint numRings = 8, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]){
    if (numSegments < 3) numSegments = 3;
    if (numRings < 1) numRings = 1;

    float halfHeight = height / 2.0f;
    auto cI = cast(float)paletteOrdinal(color);

    computeWall(this, radius, halfHeight, numSegments, cI);
    capsuleCap(this, radius, halfHeight, numSegments, numRings, cI, true);    // top hemisphere
    capsuleCap(this, radius, halfHeight, numSegments, numRings, cI, false);   // bottom hemisphere

    instances = [DrawInstance()];
    meshes["Capsule"] = Mesh([0, cast(uint)vertices.length]);
    topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    mName = typeof(this).stringof;
  }
}

/** One hemisphere cap; equator ring aligns to the wall at y = ±halfHeight, apex points outward. */
void capsuleCap(T)(T o, float radius, float halfHeight, uint numSegments, uint numRings, float color, bool top) {
  float cy = top ? halfHeight : -halfHeight;
  float dir = top ? 1.0f : -1.0f;
  foreach (ring; 0 .. numRings) {
    float phi0 = (PI / 2.0f) * (cast(float)ring / numRings);          // 0 = equator, PI/2 = pole
    float phi1 = (PI / 2.0f) * (cast(float)(ring + 1) / numRings);
    float r0 = radius * cos(phi0), y0 = cy + dir * radius * sin(phi0);
    float r1 = radius * cos(phi1), y1 = cy + dir * radius * sin(phi1);
    foreach (seg; 0 .. numSegments) {
      float[2] t = computeThetas(seg, numSegments);
      float[3] a = [r0*cos(t[0]), y0, r0*sin(t[0])];
      float[3] b = [r0*cos(t[1]), y0, r0*sin(t[1])];
      float[3] c = [r1*cos(t[1]), y1, r1*sin(t[1])];
      float[3] d = [r1*cos(t[0]), y1, r1*sin(t[0])];
      uint v = cast(uint)o.vertices.length;
      o.vertices ~= Vertex(a, normalize([a.x, a.y - cy, a.z]), [-1.0f, color, 1.0f], [0.0f, 0.0f]);
      o.vertices ~= Vertex(b, normalize([b.x, b.y - cy, b.z]), [-1.0f, color, 1.0f], [1.0f, 0.0f]);
      o.vertices ~= Vertex(c, normalize([c.x, c.y - cy, c.z]), [-1.0f, color, 1.0f], [1.0f, 1.0f]);
      o.vertices ~= Vertex(d, normalize([d.x, d.y - cy, d.z]), [-1.0f, color, 1.0f], [0.0f, 1.0f]);
      if (top) o.indices ~= [v, v+1, v+2, v, v+2, v+3];
      else     o.indices ~= [v+2, v+1, v, v+3, v+2, v];   // mirror winding for the downward cap
    }
  }
}
