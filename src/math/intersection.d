/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : multiply;
import vector : x,y,z, vAdd, vMul;

/** Intersection structure
 */
struct Intersection{
  bool intersects = false;    /// Does it intersect
  float[3] intersection;      /// Point of intersection in
  float[3] intersectionOut;   /// Point of intersection out
  float tmin;                 /// Min Distance of intersection
  float tmax;                 /// Max Distance of intersection
  uint idx;                   /// Index of intersected object
  alias intersects this;
}

/** Compute the XZ position where a ray intersects a horizontal plane at height y */
float[3] rayAtY(float[3][2] ray, float y) {
  float t = (y - ray[0].y) / ray[1].y;
  return [ray[0].x + ray[1].x * t, y, ray[0].z + ray[1].z * t];
}

/** Compute the intersection between a ray and a bounding box
 */
@nogc pure Intersection intersects(const float[3][2] ray, const BoundingBox box, size_t instance = 0) {
  Intersection i;
  if (instance >= box.instances.length){ assert(0, "No BoundingBox Instance"); return i; }
  float[3] bmin = [ float.max,  float.max,  float.max];
  float[3] bmax = [-float.max, -float.max, -float.max];
  foreach(v; box.vertices) {
    float[3] p = box.instances[0].matrix.multiply(v.position);
    if (p.x < bmin[0]) bmin[0] = p.x;
    if (p.y < bmin[1]) bmin[1] = p.y;
    if (p.z < bmin[2]) bmin[2] = p.z;
    if (p.x > bmax[0]) bmax[0] = p.x;
    if (p.y > bmax[1]) bmax[1] = p.y;
    if (p.z > bmax[2]) bmax[2] = p.z;
  }

  i.tmin = (bmin.x - ray[0].x) / ray[1].x;
  i.tmax = (bmax.x - ray[0].x) / ray[1].x; 
  if (i.tmin > i.tmax) swap(i.tmin, i.tmax);

  float tymin = (bmin.y - ray[0].y) / ray[1].y;
  float tymax = (bmax.y - ray[0].y) / ray[1].y; 
  if (tymin > tymax) swap(tymin, tymax);

  if ((i.tmin > tymax) || (tymin > i.tmax)) return i;

  if (tymin > i.tmin) i.tmin = tymin;
  if (tymax < i.tmax) i.tmax = tymax;

  float tzmin = (bmin.z - ray[0].z) / ray[1].z;
  float tzmax = (bmax.z - ray[0].z) / ray[1].z; 
  if (tzmin > tzmax) swap(tzmin, tzmax);

  if ((i.tmin > tzmax) || (tzmin > i.tmax)) return i;
  if (tzmin > i.tmin) i.tmin = tzmin;
  if (tzmax < i.tmax) i.tmax = tzmax;

  if (i.tmax > -0.5f){
   /* Debug for intercept calculation
    SDL_Log("tmin: %s, tmax: %s", tmin, tmax);
    SDL_Log("tymin: %s, tymax: %s", tymin, tymax);
    SDL_Log("tzmin: %s, tzmax: %s", tzmin, tzmax); */
    i.intersection = ray[0].vAdd(ray[1].vMul(i.tmin));
    i.intersectionOut = ray[0].vAdd(ray[1].vMul(i.tmax));
    i.intersects = true;
  }
  return i;
}

