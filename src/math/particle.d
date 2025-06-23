/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import vector : Vector, vMul, vAdd, magnitude;
import quaternion : Quaternion;

/** A single particle
 */
struct Particle {
  float[4] position;    /// Position
  float[4] velocity;    /// Velocity
  float mass;           /// Mass
  float life;           /// Life
  float random1;        /// Random number
  float random2;        /// Random number
}
