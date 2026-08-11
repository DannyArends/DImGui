/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import normals : computeTangents;
import icosahedron : refineIcosahedron;

/** Geodesic sphere: an icosahedron subdivided `level` times. */
class Sphere : Icosahedron {
  this(uint level = 3, float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]) {
    super(color);
    this.computeTangents();
    this.refineIcosahedron(level, color);
    mName = typeof(this).stringof;
  }
}
