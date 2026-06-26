/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import vector : x, y, z;
import quaternion : Quaternion, w;
import matrix : Matrix, multiply;

alias Quaternion Plane;

/** Extract from column-major VP matrix */
Plane[6] extractFrustum(const Matrix vp) @nogc pure nothrow {
  Plane[6] p;
  foreach (i; 0..4) {  // i = column index
    p[0][i] = vp[i*4 + 3] + vp[i*4 + 0];  // left:   row3 + row0
    p[1][i] = vp[i*4 + 3] - vp[i*4 + 0];  // right:  row3 - row0
    p[2][i] = vp[i*4 + 3] + vp[i*4 + 1];  // bottom: row3 + row1
    p[3][i] = vp[i*4 + 3] - vp[i*4 + 1];  // top:    row3 - row1
    p[4][i] = vp[i*4 + 2];                // near:   row2
    p[5][i] = vp[i*4 + 3] - vp[i*4 + 2];  // far:    row3 - row2
  }
  return p;
}

bool aabbInFrustum(const Plane[6] planes, const float[3] mn, const float[3] mx) @nogc pure nothrow {
  foreach (ref p; planes) {
    float[3] pv = [p.x >= 0 ? mx[0] : mn[0], p.y >= 0 ? mx[1] : mn[1], p.z >= 0 ? mx[2] : mn[2]];
    if (p.x*pv.x + p.y*pv.y + p.z*pv.z + p.w < 0) return false;
  }
  return true;
}

@nogc void cullFrustum(T)(ref T[] objects, const Plane[6] frustum) nothrow {
  for (size_t x = 0; x < objects.length; x++) {
    if(objects[x].box is null) continue;
    if(objects[x].skipFrustum) continue;
    objects[x].inFrustum = false;
    for (size_t i = 0; i < objects[x].box.instances.length; i++) {
      auto b = objects[x].box.boundsWorld(i);
      if(aabbInFrustum(frustum, b[0], b[1])) { objects[x].inFrustum = true; break; }
    }
    if(objects[x].onFrustumUpdate) objects[x].onFrustumUpdate(objects[x].inFrustum);
  }
}

unittest {
  import std.math : isClose;
  import vector : approx;
  import matrix : orthogonal;

  // symmetric ortho box: x in [-10,10], y in [-10,10], z in [-100,0] (identity view, so VP == projection)
  auto planes = extractFrustum(orthogonal(-10.0f, 10.0f, -10.0f, 10.0f, 0.0f, 100.0f));

  // pin the extracted LEFT plane independently of aabbInFrustum:
  // 0.1*x + 1 >= 0  ->  x >= -10
  assert(approx(cast(float[4])planes[0], [0.1f, 0.0f, 0.0f, 1.0f]));

  // box sitting at the centre of the frustum is inside
  assert( aabbInFrustum(planes, [-1.0f, -1.0f, -51.0f], [1.0f, 1.0f, -49.0f]));

  // box far off to +X fails the right plane
  assert(!aabbInFrustum(planes, [50.0f, -1.0f, -51.0f], [52.0f, 1.0f, -49.0f]));

  // box behind the near plane (z > 0) is culled
  assert(!aabbInFrustum(planes, [-1.0f, -1.0f, 10.0f], [1.0f, 1.0f, 20.0f]));

  // box beyond the far plane (z < -100) is culled
  assert(!aabbInFrustum(planes, [-1.0f, -1.0f, -150.0f], [1.0f, 1.0f, -120.0f]));

  // a box spanning the whole world is (at least partially) inside
  assert( aabbInFrustum(planes, [-999.0f, -999.0f, -999.0f], [999.0f, 999.0f, 999.0f]));
}
