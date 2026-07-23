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
  float[4] worldNormal = [0.0f, 1.0f, 0.0f, 0.0f];   /// baked world-space normal (xyz); w unused
  float[4] worldTangent = [1.0f, 0.0f, 0.0f, 1.0f];  /// baked world-space tangent (xyz) + handedness (w)
  Matrix matrix = Matrix.init;                  /// Matrix
  alias matrix this;

  static assert(DrawInstance.color.offsetof  == 16);
  static assert(DrawInstance.uvRect.offsetof == 32);
  static assert(DrawInstance.worldNormal.offsetof == 48);
  static assert(DrawInstance.worldTangent.offsetof == 64);
  static assert(DrawInstance.matrix.offsetof == 80);

  /** NEVER AGAIN: this(uint[2] d){ meshdef = [cast(int)d[0], cast(int)d[1]]; } - Caused a release mode crash */
  /** Transform (+ optional material / color / UV). Covers primitives, dwarves, features, blocks, glyphs. */
  @nogc this(Matrix m, int mat = -1, float[4] c = [1.0f, 1.0f, 1.0f, 1.0f], float[4] uv = [0.0f, 0.0f, 1.0f, 1.0f]) nothrow {
    matrix = m; meshdef[2] = mat; color = c; uvRect = uv;
  }

  /** Packed face transform (+ optional material). For voxel faces (chunk/water/clouds). */
  @nogc this(float[12] fd, int mat, int f) nothrow {
    this(Matrix([fd[0],fd[1],fd[2],0, fd[3],fd[4],fd[5],0, fd[6],fd[7],fd[8],0, fd[9],fd[10],fd[11],1]), mat);
    worldNormal = [FACE_OFFSETS[f][0], FACE_OFFSETS[f][1], FACE_OFFSETS[f][2], 0];
    worldTangent = [FACE_TANGENT[f][0], FACE_TANGENT[f][1], FACE_TANGENT[f][2], 1];
  }
}
