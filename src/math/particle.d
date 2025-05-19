/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.random : uniform;
import std.math : abs;

import vector : Vector, vMul, vAdd, magnitude;
import quaternion : Quaternion;

/** A single particle
 */
struct Particle {
  float[3] position;   /// Position
  align(16) float[3] velocity;   /// Velocity
  float mass = 1.0f;   /// Mass
  float life = 1.0f;   /// Life
  float random = 0.0f; /// Random number
  float _padding_end;
  @property @nogc float[3] energy() nothrow { /// Vectored energy (Velocity times Mass)
    return(velocity.vMul(mass)); 
  }
}
