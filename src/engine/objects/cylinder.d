/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import vector : x, y, z, magnitude, cross, mean;
import cone : computeBasePositions, computeCap, computeThetas;

/** Cylinder
 * Defines a cylinder geometry with a specified radius, height, and number of segments.
 * The bottom base is centered at (0,0,0) and the top base is centered at (0, height, 0). */
class Cylinder : Geometry {
  this(float radius = 0.5f, float height = 1.0f, uint numSegments = 128, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]){
    if (numSegments < 3) { numSegments = 3; }

    // Calculate half height for centering
    float halfHeight = height / 2.0f;

    computeWall(this, radius, halfHeight, numSegments, color);
    computeCap(this, [0.0f, halfHeight, 0.0f], [0.0f, 1.0f, 0.0f], radius, numSegments, color); // Top cap
    computeCap(this, [0.0f, -halfHeight, 0.0f], [0.0f, -1.0f, 0.0f], radius, numSegments, color); // Bottom cap

    instances = [DrawInstance()];
    meshes["Cylinder"] = Mesh([0, cast(uint)vertices.length]);
    geometry = (){ return(typeof(this).stringof); };
  }
}

/** Cylindrical side wall: numSegments quads spanning y = ±halfHeight. Shared by Cylinder and Capsule. */
pure void computeWall(T)(T o, float radius, float halfHeight, uint numSegments, float[4] color) nothrow {
  for (uint i = 0; i < numSegments; ++i) {
    float[2] thetas = computeThetas(i, numSegments);
    float[3][2] p = computeBasePositions(radius, thetas);
    float avg = mean(thetas);
    float[3] n = [cos(avg), 0.0f, sin(avg)];
    float[4] tan = [-sin(avg), 0.0f, cos(avg), 1.0f];
    uint v = cast(uint)o.vertices.length;
    o.vertices ~= Vertex([p[0].x, -halfHeight, p[0].z], [0.0f, 0.0f], color, n, tan);
    o.vertices ~= Vertex([p[1].x, -halfHeight, p[1].z], [1.0f, 0.0f], color, n, tan);
    o.vertices ~= Vertex([p[1].x,  halfHeight, p[1].z], [1.0f, 1.0f], color, n, tan);
    o.vertices ~= Vertex([p[0].x,  halfHeight, p[0].z], [0.0f, 1.0f], color, n, tan);
    o.indices ~= [v+2, v+1, v, v, v+3, v+2];
  }
}
