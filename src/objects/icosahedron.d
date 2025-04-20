/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

import std.math : PI, atan, sin, cos, tan, sqrt, atan2, asin;

import geometry : Geometry, faces, addVertex;
import vector : midpoint, cross, vSub, normalize;
import vertex : Vertex;

const float x = 0.426943;
const float y = 0.904279;

/** Icosahedron
 */
class Icosahedron : Geometry {
   this(){
    vertices = [ 
                 Vertex([-x, y,0], toTC([-x, y,0]), [1.0f, 1.0f, 1.0f, 1.0f]), 
                 Vertex([ x, y,0], toTC([ x, y,0]), [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([-x,-y,0], toTC([-x,-y,0]), [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([ x,-y,0], toTC([ x,-y,0]), [1.0f, 1.0f, 1.0f, 1.0f]),
                                                            
                 Vertex([0,-x, y], toTC([0,-x, y]), [1.0f, 1.0f, 1.0f, 1.0f]), 
                 Vertex([0, x, y], toTC([0, x, y]), [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([0,-x,-y], toTC([0,-x,-y]), [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([0, x,-y], toTC([0, x,-y]), [1.0f, 1.0f, 1.0f, 1.0f]),
                                                            
                 Vertex([ y,0,-x], toTC([ y,0,-x]), [1.0f, 1.0f, 1.0f, 1.0f]), 
                 Vertex([ y,0, x], toTC([ y,0, x]), [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([-y,0,-x], toTC([-y,0,-x]), [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([-y,0, x], toTC([-y,0, x]), [1.0f, 1.0f, 1.0f, 1.0f])
               ];
    indices = [0, 11, 5, 0,  5,  1,  0,  1,  7,  0, 7, 10, 0, 10, 11,
               1,  5, 9, 5, 11,  4, 11, 10,  2, 10, 7,  6, 7,  1,  8,
               3,  9, 4, 3,  4,  2,  3,  2,  6,  3, 6,  8, 3,  8,  9,
               4,  9, 5, 2,  4, 11,  6,  2, 10,  8, 6,  7, 9,  8,  1];
    topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
  }
}

@nogc  pure float[2] toTC(float[3] p) nothrow {
    float normalisedX =  0.0f;
    float normalisedZ = -1.0f;
    float xSq = p[0] * p[0];
    float zSq = p[2] * p[2];
    if ((xSq + zSq) > 0.0f) {
      normalisedX = sqrt(xSq / (xSq + zSq));
      normalisedZ = sqrt(zSq / (xSq + zSq));
      if (p[0] < 0.0f) normalisedX = -normalisedX;
      if (p[2] < 0.0f) normalisedZ = -normalisedZ;
    }
    float[2] texCoord = [0.0f, (-p[1] + 1.0f) / 2.0f];
    if (normalisedZ == 0.0f) {
      texCoord[0] = ((normalisedX * PI) / 2.0f);
    } else {
      texCoord[0] = atan(normalisedX / normalisedZ);
    }
    if (normalisedZ < 0.0f)  texCoord[0] += PI;
    if (texCoord[0] < 0.0f)  texCoord[0] += 2.0f * PI;      // Shift U coordinate between 0-2pi

    texCoord[0] /= (2.0f * PI);                             // Normalize U coordinate range 0-2pi -> 0, 1
    return(texCoord);
}

void refineIcosahedron(ref Geometry object, uint recursionLevel = 1) {
  float[3] p0, p1, p2, a,b,c;
  uint ia, ib, ic;
  for (uint i = 0; i < recursionLevel; i++) {
    uint[] indices;
    foreach(uint[3] tri; object.faces()) {
      p0 = object.vertices[tri[0]].position;
      p1 = object.vertices[tri[1]].position;
      p2 = object.vertices[tri[2]].position;

      // Compute normalized midpoint
      a = midpoint(p0, p1, true);
      b = midpoint(p1, p2, true);
      c = midpoint(p2, p0, true);

      ia = object.addVertex(Vertex(a, toTC(a)));
      ib = object.addVertex(Vertex(b, toTC(b)));
      ic = object.addVertex(Vertex(c, toTC(c)));

      // Split triangle into 4 new triangles
      indices ~= tri[0]; indices ~= ia; indices ~= ic;
      indices ~= tri[1]; indices ~= ib; indices ~= ia;
      indices ~= tri[2]; indices ~= ic; indices ~= ib;
      indices ~= ia; indices ~= ib; indices ~= ic;
    }
    object.indices = indices;
  }
  for (uint i = 0; i < (object.indices.length-2); i+=3) {
    a = [object.vertices[object.indices[i+0]].texCoord[0], object.vertices[object.indices[i+0]].texCoord[1], 0.0f];
    b = [object.vertices[object.indices[i+1]].texCoord[0], object.vertices[object.indices[i+1]].texCoord[1], 0.0f];
    c = [object.vertices[object.indices[i+2]].texCoord[0], object.vertices[object.indices[i+2]].texCoord[1], 0.0f];

    float[3] cp = cross(vSub(a, b), vSub(c, b));
    if(cp[2] <= 0) {                                        // Face crosses a texture boundary
      for (uint j = i; j < i + 3; j++){
        uint index = object.indices[j];
        if (object.vertices[index].texCoord[0] >= 0.9f){    // On the other side, add new vertex
          Vertex vDup = object.vertices[index];
          vDup.texCoord[0] -= 1.0f;                         // Move texture coord
          object.indices[j] = object.addVertex(vDup);       // Insert vertex and update index array
        }
      }
    }
  }
}

