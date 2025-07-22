/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : Instance, Geometry;
import vector : x,y,z, magnitude, cross;
import vertex : Vertex;
import mesh : Mesh;
import cone : computeThetas, computeBasePositions, computeCap;

/** Cylinder
 * Defines a cylinder geometry with a specified radius, height, and number of segments.
 * The bottom base is centered at (0,0,0) and the top base is centered at (0, height, 0).
 */
class Cylinder : Geometry {
  this(float radius = 0.5f, float height = 1.0f, uint numSegments = 128, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]){
    if (numSegments < 3) { numSegments = 3; }

    // Calculate half height for centering
    float halfHeight = height / 2.0f;

    for (uint i = 0; i < numSegments; ++i) {
      float[2] thetas = computeThetas(i, numSegments);
      float[3][2] bottomPositions = computeBasePositions(radius, thetas);

      float avgTheta = (thetas[0] + thetas[1]) / 2.0f;
      float[3] sideFaceNormal = [cos(avgTheta), 0.0f, sin(avgTheta)];

      uint vIdx = cast(uint)vertices.length;
      vertices ~= Vertex([bottomPositions[0].x, bottomPositions[0].y - halfHeight, bottomPositions[0].z], [0.0f, 0.0f], color, sideFaceNormal);
      vertices ~= Vertex([bottomPositions[1].x, bottomPositions[1].y - halfHeight, bottomPositions[1].z], [1.0f, 0.0f], color, sideFaceNormal);
      vertices ~= Vertex([bottomPositions[1].x, height - halfHeight, bottomPositions[1].z], [1.0f, 1.0f], color, sideFaceNormal);
      vertices ~= Vertex([bottomPositions[0].x, height - halfHeight, bottomPositions[0].z], [0.0f, 1.0f], color, sideFaceNormal);

      indices ~= [vIdx+2, vIdx + 1, vIdx, vIdx, vIdx + 3, vIdx + 2];
    }
    // Adjust cap positions by subtracting halfHeight
    this.computeCap([0.0f, halfHeight, 0.0f], [0.0f, 1.0f, 0.0f], radius, numSegments, color); // Top cap
    this.computeCap([0.0f, -halfHeight, 0.0f], [0.0f, -1.0f, 0.0f], radius, numSegments, color); // Bottom cap

    instances = [Instance()];
    meshes["Cylinder"] = Mesh([0, cast(uint)vertices.length]);
    name = (){ return(typeof(this).stringof); };
  }
}
