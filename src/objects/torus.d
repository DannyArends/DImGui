/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import geometry : Instance, Geometry;
import vertex : Vertex;
import mesh : Mesh;
import std.math : PI, sin, cos;

/** Torus
 * Defines a torus geometry with a major radius, minor radius, and segment counts.
 * The lowest point of the torus (bottom of the inner curve) is at (0,0,0).
 */
class Torus : Geometry {
  this(float[2] radii = [0.1f, 0.4f], uint[2] segments = [16, 32], float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]){
    if (segments[0] < 3) { segments[0] = 3; }
    if (segments[1] < 3) { segments[1] = 3; }

    for (uint i = 0; i <= segments[1]; ++i) {
      float u = cast(float)i / segments[1] * 2.0f * PI;
      for (uint j = 0; j <= segments[0]; ++j) {
        float v = cast(float)j / segments[0] * 2.0f * PI;
        float s =(radii[1] + radii[0] * cos(v));

        float[3] position = [s * cos(u), radii[0] * sin(v) + radii[0], s * sin(u)];
        float[3] normal = [cos(v) * cos(u), sin(v), cos(v) * sin(u)];
        vertices ~= Vertex(position, [i / cast(float)(segments[1]), j / cast(float)(segments[0])], color, normal);

        if(i < segments[1] && j < segments[0]){
          uint p0 = (i * (segments[0] + 1)) + j;
          uint p1 = ((i + 1) * (segments[0] + 1)) + j;
          uint p2 = ((i + 1) * (segments[0] + 1)) + (j + 1);
          uint p3 = (i * (segments[0] + 1)) + (j + 1);
          indices ~= [p0, p1, p2, p2, p3, p0];
        }
      }
    }

    instances = [Instance()];
    meshes["Torus"] = Mesh([0, cast(uint)vertices.length]);
    name = (){ return(typeof(this).stringof); };
  }
}
