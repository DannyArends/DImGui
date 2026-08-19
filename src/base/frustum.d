/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import vector : x, y, z;
import quaternion : Quaternion, w;
import matrix : Matrix, multiply;

alias Plane = Quaternion;   /// a frustum plane: xyz = normal, w = distance

/** Extract the 6 frustum planes (L,R,B,T,N,F) from a column-major view-projection matrix. 
    Not normalized, only the sign of the plane test matters for culling */
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

/** True if the AABB is at least partially inside the frustum. */
bool aabbInFrustum(const Plane[6] planes, const float[3][2] b) @nogc pure nothrow {
  foreach (ref p; planes) {
    float[3] pv = [p.x >= 0 ? b[1][0] : b[0][0], p.y >= 0 ? b[1][1] : b[0][1], p.z >= 0 ? b[1][2] : b[0][2]];
    if (p.x*pv.x + p.y*pv.y + p.z*pv.z + p.w < 0) return false;
  }
  return true;
}

/** Flag each object's box visible/invisible by testing its AABB against the frustum. */
@nogc void cullFrustum(T)(ref T[] objects, const Plane[6] frustum) nothrow {
  for (size_t i = 0; i < objects.length; i++) {
    if(objects[i].box is null) continue;
    objects[i].box.visible = aabbInFrustum(frustum, objects[i].box);
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
  assert( aabbInFrustum(planes, [[-1.0f, -1.0f, -51.0f], [1.0f, 1.0f, -49.0f]]));

  // box far off to +X fails the right plane
  assert(!aabbInFrustum(planes, [[50.0f, -1.0f, -51.0f], [52.0f, 1.0f, -49.0f]]));

  // box behind the near plane (z > 0) is culled
  assert(!aabbInFrustum(planes, [[-1.0f, -1.0f, 10.0f], [1.0f, 1.0f, 20.0f]]));

  // box beyond the far plane (z < -100) is culled
  assert(!aabbInFrustum(planes, [[-1.0f, -1.0f, -150.0f], [1.0f, 1.0f, -120.0f]]));

  // a box spanning the whole world is (at least partially) inside
  assert( aabbInFrustum(planes, [[-999.0f, -999.0f, -999.0f], [999.0f, 999.0f, 999.0f]]));
}
