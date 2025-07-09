/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

import matrix : Matrix;

struct Light {
  Matrix lightSpaceMatrix;
  float[4] position   = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light Position
  float[4] intensity  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light intensity
  float[4] direction  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light direction
  float[4] properties = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light properties [ambient, attenuation, angle]
}

enum Lights : Light {
  White = Light(Matrix.init, [0.0f,   1.0f, 0.0f, 0.0f], [0.2f, 0.2f, 0.2f, 1.0f], [0.0f,   0.0f, 0.0f, 0.0f], [1.0f, 0.0f, 0.0f, 0.0f]),
  Red   = Light(Matrix.init, [4.0f,  15.0f, 0.0f, 1.0f], [4.0f, 0.0f, 0.0f, 1.0f], [0.1f, -1.0f, 0.1f, 0.0f], [0.0f, 0.01f, 40.0f, 0.0f]),
  Green = Light(Matrix.init, [0.0f,  15.0f, 4.0f, 1.0f], [0.0f, 4.0f, 0.0f, 1.0f], [0.1f, -1.0f, 0.1f, 0.0f], [0.0f, 0.01f, 40.0f, 0.0f]),
  Blue  = Light(Matrix.init, [0.0f,  15.0f, 0.0f, 1.0f], [0.0f, 0.0f, 4.0f, 1.0f], [0.1f, -1.0f, 0.1f, 0.0f], [0.0f, 0.01f, 40.0f, 0.0f])
};

