/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import matrix : multiply;
import vector : x,y,z, vAdd, vMul;

/** Intersection structure */
struct Intersection{
  bool intersects = false;    /// Does it intersect
  float[3] intersection;      /// Point of intersection in
  float[3] intersectionOut;   /// Point of intersection out
  float tmin;                 /// Min Distance of intersection
  float tmax;                 /// Max Distance of intersection
  size_t[2] idx;              /// Index & Instance of intersected object
  alias intersects this;
}

/** Compute the XZ position where a ray intersects a horizontal plane at height y */
float[3] rayAtY(float[3][2] ray, float y) {
  float t = (y - ray[0].y) / ray[1].y;
  return [ray[0].x + ray[1].x * t, y, ray[0].z + ray[1].z * t];
}

/** Compute the intersection between a ray and bmin and bmin */
@nogc pure Intersection intersects(const float[3][2] ray, const float[3] bmin, const float[3] bmax, size_t index, size_t instance) {
  Intersection i;

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

  if (i.tmax >= 0.0f) {
   /* Debug for intercept calculation
    SDL_Log("tmin: %s, tmax: %s", tmin, tmax);
    SDL_Log("tymin: %s, tymax: %s", tymin, tymax);
    SDL_Log("tzmin: %s, tzmax: %s", tzmin, tzmax); */
    i.intersection = ray[0].vAdd(ray[1].vMul(i.tmin));
    i.intersectionOut = ray[0].vAdd(ray[1].vMul(i.tmax));
    i.intersects = true;
    i.idx = [index, instance];
  }
  return(i);
}

/** Compute the intersection between a ray and a bounding box */
pure Intersection[] intersects(T)(const float[3][2] ray, const T box, size_t index) {
  Intersection[] intersections;
  if(!ray.intersects(box.wmin, box.wmax, index, 0).intersects) { return(intersections); }
  for(size_t instance = 0; instance < box.instances.length; instance++) {
    auto intersection = ray.intersects(box.bmin(instance), box.bmax(instance), index, instance);
    if(intersection.intersects){ intersections ~= intersection; }
  }
  return(intersections);
}

unittest {
  import std.math : isClose;
  import vector : approx;

  float[3] bmin = [-1.0f, -1.0f, -1.0f];
  float[3] bmax = [ 1.0f,  1.0f,  1.0f];

  // default Intersection is falsey via `alias intersects this`
  assert(!Intersection.init);

  // head-on hit: ray from -Z aimed at +Z. Note dir.x==dir.y==0, so the X/Y
  // slabs go through inf arithmetic -- this is the case worth pinning.
  float[3][2] hit = [[0.0f, 0.0f, -5.0f], [0.0f, 0.0f, 1.0f]];
  auto a = hit.intersects(bmin, bmax, 7, 3);
  assert(a.intersects);
  assert(approx(a.intersection,    [0.0f, 0.0f, -1.0f]));   // enters front face
  assert(approx(a.intersectionOut, [0.0f, 0.0f,  1.0f]));   // exits back face
  assert(isClose(a.tmin, 4.0f) && isClose(a.tmax, 6.0f));
  assert(a.idx == [cast(size_t)7, cast(size_t)3]);          // index + instance stored

  // miss: same ray direction but pointing AWAY from the box (box is behind).
  // tmax ends up <= -0.5f, so it is rejected.
  float[3][2] behind = [[0.0f, 0.0f, 5.0f], [0.0f, 0.0f, 1.0f]];
  assert(!behind.intersects(bmin, bmax, 0, 0).intersects);

  // miss: ray offset on X so it never enters the box's X slab
  float[3][2] offset = [[5.0f, 0.0f, -5.0f], [0.0f, 0.0f, 1.0f]];
  assert(!offset.intersects(bmin, bmax, 0, 0).intersects);

  // rayAtY: drop a diagonal ray onto the y=0 plane
  float[3][2] down = [[0.0f, 10.0f, 0.0f], [1.0f, -1.0f, 0.0f]];
  assert(approx(rayAtY(down, 0.0f), [10.0f, 0.0f, 0.0f]));
}