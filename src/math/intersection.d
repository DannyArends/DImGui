/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

import std.algorithm.mutation: swap;

import boundingbox : BoundingBox;
import matrix : multiply;
import vector : x,y,z, vAdd, vMul;

struct Intersection{
  bool intersects = false;
  float[3] intersection;
  float[3] intersectionOut;
  alias intersects this;
}

@nogc pure Intersection intersects(const float[3][2] ray, const BoundingBox box)  {
  Intersection i;
  float[3] bmin = box.instances[0].matrix.multiply(box.min);
  float[3] bmax = box.instances[0].matrix.multiply(box.max);

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

  if (tmax > -0.5f){
   /* Debug for intercept calculation
    writefln("tmin: %s, tmax: %s", tmin, tmax);
    writefln("tymin: %s, tymax: %s", tymin, tymax);
    writefln("tzmin: %s, tzmax: %s", tzmin, tzmax); */
    i.intersection = ray[0].vAdd(ray[1].vMul(tmin));
    i.intersectionOut = ray[0].vAdd(ray[1].vMul(tmax));
    i.intersects = true;
  }
  return i;
}
