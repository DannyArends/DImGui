/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import vector : x, y, z;

/** Accumulates a min/max AABB. */
struct Bounds {
  float[3] min = [ float.max, float.max, float.max];
  float[3] max = [-float.max,-float.max,-float.max];

  @nogc pure void update(const float[3] v) nothrow {
    if (v.x < min[0]) min[0] = v.x;
    if (v.y < min[1]) min[1] = v.y;
    if (v.z < min[2]) min[2] = v.z;
    if (v.x > max[0]) max[0] = v.x;
    if (v.y > max[1]) max[1] = v.y;
    if (v.z > max[2]) max[2] = v.z;
  }
  @property @nogc pure float[3] size() nothrow const { float[3] s = max[] - min[]; return(s); }
}

/** A cullable span [first, first+count) of an object's instance buffer. */
struct DrawRange {
  uint first = 0;        /// First instance index
  uint count = 0;        /// Instance count
  bool visible = true;   /// Cached frustum result

  /** Union this range's per-instance world-AABBs into one AABB. */
  @nogc float[3][2] bounds(const float[3][2][] world) const nothrow {
    Bounds b;
    foreach(i; first .. first + count) {
      if(i >= world.length) break;
      b.update(world[i][0]); b.update(world[i][1]);
    }
    return [b.min, b.max];
  }
}
