/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.algorithm.mutation: swap;

import boundingbox : BoundingBox;
import geometry : Geometry;
import matrix : multiply;
import vector : vAdd, vSub, vMul, x, y, z;
import vertex : Vertex;

/** Line
 */
class Line : Geometry {
  this(){
    vertices = [
      Vertex([ 0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([ 0.0f, 1.0f, 0.0f ], [  0.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 1.0f ])
    ];
    indices = [0, 1];
    topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    onTick = (ref App app, ref Geometry obj) { obj.deAllocate = true; }; // Set the deAllocate flag onTick
    name = (){ return(typeof(this).stringof); };
  }
}

/** Intersection
 */
struct Intersection {
  bool intersects = false;
  float[3] intersection;
  float[3] intersectionOut;
  alias intersects this;
}

/** Ray
 */
alias float[3][2] Ray;

/** Create a Line from a Ray
 */
Line createLine(Ray ray, float length = 50){
  Line line = new Line();
  line.vertices[0].position = ray[0];
  line.vertices[1].position = ray[0].vAdd(ray[1].vMul(length));
  return(line);
}

@nogc pure Intersection intersects(Ray ray, const BoundingBox box) nothrow {
  Intersection i;

  float[3] bmin = box.instances[0].multiply(box.min);
  float[3] bmax = box.instances[0].multiply(box.max);

  float tmin = (bmin.x - ray[0].x) / ray[1].x;
  float tmax = (bmax.x - ray[0].x) / ray[1].x; 
  if (tmin > tmax) swap(tmin, tmax);

  float tymin = (bmin.y - ray[0].y) / ray[1].y;
  float tymax = (bmax.y - ray[0].y) / ray[1].y; 
  if (tymin > tymax) swap(tymin, tymax);

  if ((tmin > tymax) || (tymin > tmax)) return i;

  if (tymin > tmin) tmin = tymin;
  if (tymax < tmax) tmax = tymax;

  float tzmin = (bmin.z - ray[0].z) / ray[1].z;
  float tzmax = (bmax.z - ray[0].z) / ray[1].z; 
  if (tzmin > tzmax) swap(tzmin, tzmax);

  if ((tmin > tzmax) || (tzmin > tmax)) return i;
  if (tzmin > tmin) tmin = tzmin;
  if (tzmax < tmax) tmax = tzmax;

  if (tmax > -0.5f) {
    i.intersection = ray[0].vAdd(ray[1].vMul(tmin));
    i.intersectionOut = ray[0].vAdd(ray[1].vMul(tmax));
    i.intersects = true;
  }
  return i;
}

