/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** An instance of a Geometry */
struct DrawInstance {
  int[4] meshdef = [0, 0, -1, 0];               /// Mesh range [start, end, material, unused] in meshSSBO; material -1 = use mesh material
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// Color
  float[4] uvRect = [0.0f, 0.0f, 1.0f, 1.0f];   /// UV remap [offsetX, offsetY, scaleX, scaleY]; identity = full texture
  Matrix matrix = Matrix.init;                  /// Matrix
  Matrix normal = Matrix.init;                  /// Normal matrix
  alias matrix this;

  static assert(DrawInstance.color.offsetof  == 16);
  static assert(DrawInstance.uvRect.offsetof == 32);
  static assert(DrawInstance.matrix.offsetof == 48);
  static assert(DrawInstance.normal.offsetof == 112);

  /** NEVER AGAIN: this(uint[2] d){ meshdef = [cast(int)d[0], cast(int)d[1]]; } - Caused a release mode crash */
  /** Transform (+ optional material / color / UV). Covers primitives, dwarves, features, blocks, glyphs. */
  @nogc this(Matrix m, int mat = -1, float[4] c = [1.0f, 1.0f, 1.0f, 1.0f], float[4] uv = [0.0f, 0.0f, 1.0f, 1.0f]) nothrow {
    matrix = m; meshdef[2] = mat; color = c; uvRect = uv;
  }
  /** Packed face transform (+ optional material). For voxel faces (chunk/water/clouds). */
  @nogc this(float[12] f, int mat = -1) nothrow { this(Matrix([f[0],f[1],f[2],0, f[3],f[4],f[5],0, f[6],f[7],f[8],0, f[9],f[10],f[11],1]), mat); }
}
