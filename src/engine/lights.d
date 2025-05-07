/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

public import includes;

struct Light {
  float[4] position  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light Position
  float[3] intensity = [0.0f, 0.0f, 0.0f];          /// Light intensity
  float ambient = 0.0f;                             /// Light intensity
  float attenuation = 0.0f;                         /// Light intensity
  float[3] direction = [0.0f, 0.0f, 0.0f];          /// Light direction
  float angle = 0.0f;                               /// Light angle
}

enum Lights : Light {
  White = Light([ 0.0f,  1.0f,  0.0f, 0.0f], [0.6f, 0.6f, 0.6f], 1.0f),
  Red   = Light([ 5.0f,  5.0f,  5.0f, 1.0f], [5.0f, 0.0f, 0.0f], 0.0f, 0.05f, [1.0f, -0.15f, 1.0f], 35),
  Green = Light([-5.0f,  5.0f,  5.0f, 1.0f], [0.0f, 1.0f, 0.0f], 0.0f, 0.05f),
  Blue  = Light([ 5.0f,  5.0f, -5.0f, 1.0f], [0.0f, 0.0f, 2.0f], 0.0f, 0.05f)
};

