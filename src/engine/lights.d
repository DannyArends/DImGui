/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

struct Light {
  float[4] position   = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light Position
  float[4] intensity  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light intensity
  float[4] direction  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light direction
  float[4] properties = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light properties [ambient, attenuation, angle]
}

enum Lights : Light {
  White = Light([ 0.0f,  1.0f,  0.0f, 0.0f], [0.1f, 0.1f, 0.1f, 1.0f], [0.0f,   0.0f, 0.0f, 0.0f], [1.0f, 0.0f, 0.0f, 0.0f]),
  Red   = Light([-5.0f,  10.0f, -5.0f, 1.0f], [4.0f, 2.0f, 2.0f, 1.0f], [1.0f, -0.95f, 1.0f, 0.0f], [0.0f, 0.01f, 45.0f, 0.0f]),
  Green = Light([-5.0f,  10.0f, -5.0f, 1.0f], [0.0f, 4.0f, 0.0f, 1.0f], [0.0f, -0.95f, 1.0f, 0.0f], [0.0f, 0.01f, 45.0f, 0.0f]),
  Blue  = Light([-5.0f,  10.0f, -5.0f, 1.0f], [0.0f, 0.0f, 4.0f, 1.0f], [1.0f, -0.95f, 0.0f, 0.0f], [0.0f, 0.01f, 45.0f, 0.0f])
};

