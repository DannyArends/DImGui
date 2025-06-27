/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import geometry : Instance, Geometry;
import vector : x,y,z, magnitude, cross;
import vertex : Vertex;
import mesh : Mesh;
import std.math : PI, sin, cos, sqrt;

/** Cone
 * Defines a cone geometry with a specified radius, height, and number of segments for its approximation.
 * The base of the cone is centered at (0,0,0) and the apex is at (0, height, 0).
 */
class Cone : Geometry {
  this(float radius = 0.5f, float height = 1.0f, uint numSegments = 32, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]){
    if (numSegments < 3) { numSegments = 3; }
    float[3] apex = [0.0f, height, 0.0f];

    for (uint i = 0; i < numSegments; ++i) {
      float[2] theta = computeThetas(i, numSegments);
      float[3][2] positions = computeBasePositions(radius, theta);

      float[3] v1 = positions[1][] - apex[];
      float[3] v2 = positions[0][] - apex[];
      float[3] normal = cross(v1, v2);         // Compute the cross product (v1 x v2) to get the face normal.

      // Normalize the calculated normal vector to unit length
      float invLength = (normal.magnitude == 0.0f) ? 0.0f : 1.0f / normal.magnitude;
      float[3] faceNormal = normal[] * invLength;

      uint vIdx = cast(uint)vertices.length;
      vertices ~= Vertex(apex, [0.5f, 0.0f], color, faceNormal);
      vertices ~= Vertex(positions[0], [0.0f, 1.0f], color, faceNormal);
      vertices ~= Vertex(positions[1], [1.0f, 1.0f], color, faceNormal);

      indices ~= [vIdx+2, vIdx + 1, vIdx];
    }
    this.computeCap([0.0f, 0.0f, 0.0f], [0.0f, -1.0f, 0.0f], radius, numSegments, color);

    instances = [Instance()];
    meshes["Cone"] = Mesh([0, cast(uint)vertices.length]);
    name = (){ return(typeof(this).stringof); };
  }
}

@nogc pure float[3][2] computeBasePositions(float radius, float[2] thetas) nothrow {
  float[3] p1 = [radius * cos(thetas[0]), 0.0f, radius * sin(thetas[0])];
  float[3] p2 = [radius * cos(thetas[1]), 0.0f, radius * sin(thetas[1])];
  return [p1, p2];
}

@nogc pure float[2] computeThetas(uint i, uint numSegments) nothrow {
  return [i * (2.0f * PI / numSegments), (i + 1) * (2.0f * PI / numSegments)];
}

@nogc pure float[2][2] computeTexCoord(float[2] thetas) nothrow {
  return [
    [0.5f + 0.5f * cos(thetas[0]), 0.5f + 0.5f * sin(thetas[0])],
    [0.5f + 0.5f * cos(thetas[1]), 0.5f + 0.5f * sin(thetas[1])]
  ];
}

pure void computeCap(T)(T geometry, float[3] center, float[3] normal, float radius, uint numSegments, float[4] color) nothrow {
  for (uint i = 0; i < numSegments; ++i) {
    float[2] thetas = computeThetas(i, numSegments);
    float[3][2] baseCirclePositions = computeBasePositions(radius, thetas);
    float[2][2] texCoords = computeTexCoord(thetas);

    float[3] p1 = [baseCirclePositions[0].x, center.y, baseCirclePositions[0].z];
    float[3] p2 = [baseCirclePositions[1].x, center.y, baseCirclePositions[1].z];

    uint vIdx = cast(uint)geometry.vertices.length;
    geometry.vertices ~= Vertex(p1, texCoords[0], color, normal);      // V0 relative to vIdx
    geometry.vertices ~= Vertex(p2, texCoords[1], color, normal);      // V1 relative to vIdx
    geometry.vertices ~= Vertex(center, [0.5f, 0.5f], color, normal);  // V2 relative to vIdx

    if (normal.y > 0.0f) {
      geometry.indices ~= [vIdx+1, vIdx, vIdx+2];
    } else {
      geometry.indices ~= [vIdx, vIdx+1, vIdx+2];
    }
  }
}
