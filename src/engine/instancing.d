/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** An instance of a Geometry */
struct DrawInstance {
  uint[2] meshdef  = [0, 0];                  /// Mesh range [start, end] in meshSSBO
  int material = -1;                          /// Material override (-1 = use mesh material)
  int pad = 0;                                /// Padding for the GLSL
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];  /// Per-instance color
  Matrix matrix = Matrix.init;
  alias matrix this;

  static assert(DrawInstance.color.offsetof  == 16);
  static assert(DrawInstance.matrix.offsetof == 32);

  this(int mat, Matrix m) { material = mat; matrix = m; }
  this(uint[2] d, Matrix m = Matrix.init) { meshdef = d; matrix = m; }
  this(uint[2] d, float[4] c, Matrix m = Matrix.init) { meshdef = d; color = c; matrix = m; }
  this(ResourceType tt, Matrix m) { this([cast(uint)tt, cast(uint)tt], m); }
  this(int mdef, float[12] f) { this([cast(uint)mdef, cast(uint)mdef], Matrix([f[0],f[1],f[2],0, f[3],f[4],f[5],0, f[6],f[7],f[8],0, f[9],f[10],f[11],1])); }
}
