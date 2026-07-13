/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** An instance of a Geometry */
struct DrawInstance {
  int[3] meshdef = [0, 0, -1];                  /// Mesh range [start, end, material, unused] in meshSSBO; material -1 = use mesh material
  int pad = 0;                                  /// Pad ?
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];    /// Color
  float[4] uvRect = [0.0f, 0.0f, 1.0f, 1.0f];   /// UV remap [offsetX, offsetY, scaleX, scaleY]; identity = full texture
  Matrix matrix = Matrix.init;                  /// Matrix
  alias matrix this;

  static assert(DrawInstance.color.offsetof  == 16);
  static assert(DrawInstance.uvRect.offsetof == 32);
  static assert(DrawInstance.matrix.offsetof == 48);

  this(int mat, Matrix m) { meshdef[2] = mat; matrix = m; }
  this(int[2] d, Matrix m = Matrix.init) { meshdef[0..2] = d[0..2]; matrix = m; }
  this(int[2] d, float[4] c, Matrix m = Matrix.init) { meshdef[0..2] = d[0..2]; color = c; matrix = m; }
  this(int mat, float[4] c, Matrix m) { meshdef[2] = mat; color = c; matrix = m; }
  this(int mdef, float[12] f) { 
    this([cast(uint)mdef, cast(uint)mdef], Matrix([f[0],f[1],f[2],0, f[3],f[4],f[5],0, f[6],f[7],f[8],0, f[9],f[10],f[11],1])); 
  }
  /** One glyph instance: local transform (position+size within the shared unit quad) and its UV rectangle in the atlas */
  this(Matrix m, float[4] uv, float[4] c = [1.0f, 1.0f, 1.0f, 1.0f]) { matrix = m; uvRect = uv; color = c; }
}
