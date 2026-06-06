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

/** Axis-aligned bounds of a set of points: returns [min, max] */
@nogc pure float[3][2] aabbOf(const float[3][] pts) nothrow {
  float[3] mn = [float.max, float.max, float.max];
  float[3] mx = [-float.max, -float.max, -float.max];
  foreach(ref p; pts) foreach(a; 0..3) { if(p[a] < mn[a]) mn[a] = p[a]; if(p[a] > mx[a]) mx[a] = p[a]; }
  return [mn, mx];
}

@nogc void cullFrustum(T)(ref T[] objects, const Plane[6] frustum) nothrow {
  for (size_t x = 0; x < objects.length; x++) {
    if(objects[x].box is null) continue;
    if(objects[x].skipFrustum) continue;
    objects[x].inFrustum = false;
    for (size_t i = 0; i < objects[x].box.instances.length; i++) {
      if (aabbInFrustum(frustum, objects[x].box.bmin(i), objects[x].box.bmax(i))) { objects[x].inFrustum = true; break; }
    }
    if(objects[x].onFrustumUpdate) objects[x].onFrustumUpdate(objects[x].inFrustum);
  }
}
