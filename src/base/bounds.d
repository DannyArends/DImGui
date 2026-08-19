/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

/** Axis-aligned bounding box stored as two corners; init is the empty box (min > max) so update() accumulates. */
struct Bounds {

  float[3][2] bounds = [[ float.max,  float.max,  float.max],     /// [0] = min corner
                        [-float.max, -float.max, -float.max]];    /// [1] = max corner
  alias bounds this;

  /** Grow the box to include point v */
  @nogc pure void update(const float[3] v) nothrow {
    foreach(k; 0..3) {
      if(v[k] < bounds[0][k]) { bounds[0][k] = v[k]; }
      if(v[k] > bounds[1][k]) { bounds[1][k] = v[k]; }
    }
  }
  /** Grow the box to include another box o */
  @nogc pure void update(const Bounds o) nothrow { update(o[0]); update(o[1]); }

  /** Min corner */
  @nogc pure @property float[3] min() nothrow const { return(bounds[0]); }
  /** Max corner */
  @nogc pure @property float[3] max() nothrow const { return(bounds[1]); }
  /** Full extent (max - min) per axis */
  @nogc pure @property float[3] size() nothrow const { float[3] s = bounds[1][] - bounds[0][]; return(s); }
  /** Centre point ((min + max) / 2) */
  @nogc pure @property float[3] center() nothrow const { float[3] c = bounds[0][] + bounds[1][]; c[] *= 0.5f; return(c); }
  /** Half-extent (size / 2) per axis */
  @nogc pure @property float[3] extent() nothrow const { float[3] e = bounds[1][] - bounds[0][]; e[] *= 0.5f; return(e); }
}
