/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import vector : x, y, z;

/** Min/max AABB; [0] = min, [1] = max. */
struct Bounds {
  float[3][2] bounds = [[ float.max,  float.max,  float.max],
                        [-float.max, -float.max, -float.max]];
  alias bounds this;

  @nogc pure void update(const float[3] v) nothrow {
    foreach(k; 0..3) {
      if(v[k] < bounds[0][k]) bounds[0][k] = v[k];
      if(v[k] > bounds[1][k]) bounds[1][k] = v[k];
    }
  }
  @nogc pure void update(const Bounds o) nothrow { update(o[0]); update(o[1]); }
  @property @nogc pure float[3] min() nothrow const { return bounds[0]; }
  @property @nogc pure float[3] max() nothrow const { return bounds[1]; }
  @property @nogc pure float[3] size() nothrow const { float[3] s = bounds[1][] - bounds[0][]; return s; }
}

/** A cullable span [first, first+count) of an object's instance buffer. */
struct DrawRange {
  uint first = 0;        /// First instance index
  uint count = 0;        /// Instance count
  bool visible = true;   /// Cached frustum result

  /** Union this range's per-instance world-AABBs into one AABB. */
  @nogc Bounds bounds(const Bounds[] world) const nothrow {
    Bounds b;
    foreach(i; first .. first + count) {
      if(i >= world.length) break;
      b.update(world[i]);
    }
    return(b);
  }
}
