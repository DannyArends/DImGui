/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** An instance of a Geometry */
struct DrawInstance {
  uint[4] meshdef = [0, 0, 0, 0];               /// Mesh Definition [start, end, mID, pad]
  Matrix matrix = Matrix.init;                  /// Instance matrix
  alias matrix this;

  this(uint[4] d, Matrix m = Matrix.init) { meshdef = d; matrix = m; }
  this(TileType tt, Matrix m) { this([cast(uint)tt, cast(uint)tt], m); }
  this(uint[2] d, Matrix m) { meshdef[0..2] = d; matrix = m; }
  this(uint mdef, float[12] f) { this([mdef, mdef], Matrix([f[0],f[1],f[2], 0, f[3],f[4],f[5], 0, f[6],f[7],f[8],0, f[9],f[10],f[11], 1])); }
}
