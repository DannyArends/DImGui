/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import std.math : sqrt, sin, cos, acos;

import vector : x,y,z, magnitude, normalize, vMul, sum;
import matrix : Matrix, radian;

/** Quaternion, stored as float[4]
 */
struct Quaternion { 
  float[4] data = [ 0.0f, 0.0f, 0.0f, 1.0f ];
  alias data this;
}

/** Returns the normalized vector of v */
@nogc pure T[4] normalize(T)(ref T[4] v) nothrow {
    float sqr = v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + v[3] * v[3];
    if(sqr == 1 || sqr == 0) return(v);
    float invrt = 1.0f / sqrt(sqr);
    v[] *= invrt;
    return(v);
}

/** Create a T[3], w as a T[4] */
@nogc pure T[4] xyzw(T)(const T[3] v, T w = 1.0f) nothrow {
    return([v.x, v.y, v.z, w]);
}

/** Create a T[3], alpha as a T[4] */
@nogc pure T[4] rgba(T)(const T[3] v, T a = 1.0f) nothrow {
    return([v.red, v.green, v.blue, a]);
}

/** Dot product between v1 and v2 */
@nogc pure T dot(T)(const T[4] v1, const T[4] v2) nothrow {
  T[4] vDot = v1[] * v2[];
  return(sum(vDot));
}

T[4] slerp(T)(T[4] start, T[4] end, float factor) {
  T[4] result;
  float dot = dot(start, end);
  if (dot < 0.0f) {    // Ensure the shortest path
    end[] = -end[];
    dot = -dot;
  }

  const float DOT_THRESHOLD = 0.9995f;
  if (dot > DOT_THRESHOLD) {
    // If the quaternions are very close, just linear interpolate (L.I.)
    result[] = start[] + factor * (end[] -start[]);
    float len = sqrt(result[0]*result[0] + result[1]*result[1] + result[2]*result[2] + result[3]*result[3]);
    if (len > 0.0f) { // Normalize
      result[] = result[] / len;
    }
    return result;
  }

  float theta_0 = acos(dot);
  float theta = theta_0 * factor;
  float sin_theta = sin(theta);
  float sin_theta_0 = sin(theta_0);

  float s0 = cos(theta) - dot * sin_theta / sin_theta_0;
  float s1 = sin_theta / sin_theta_0;

  result[] = s0 * start[] + s1 * end[];
  return result;
}

Matrix rotate(Matrix m, float[4] q) { // Quaternion (x, y, z, w)
  float x = q[0], y = q[1], z = q[2], w = q[3];

  float x2 = x + x, y2 = y + y, z2 = z + z;
  float xx = x * x2, xy = x * y2, xz = x * z2;
  float yy = y * y2, yz = y * z2, zz = z * z2;
  float wx = w * x2, wy = w * y2, wz = w * z2;

  m.data[0] = 1.0f - (yy + zz);  // m00
  m.data[1] = xy + wz;           // m10
  m.data[2] = xz - wy;           // m20
  m.data[3] = 0.0f;              // m30

  m.data[4] = xy - wz;           // m01
  m.data[5] = 1.0f - (xx + zz);  // m11
  m.data[6] = yz + wx;           // m21
  m.data[7] = 0.0f;              // m31

  m.data[8] = xz + wy;           // m02
  m.data[9] = yz - wx;           // m12
  m.data[10] = 1.0f - (xx + yy); // m22
  m.data[11] = 0.0f;             // m32

  m.data[12] = 0.0f;             // m03
  m.data[13] = 0.0f;             // m13
  m.data[14] = 0.0f;             // m23
  m.data[15] = 1.0f;             // m33
  return m;
}

/** angleAxis */
@nogc pure T[4] angleAxis(T)(T angle, T[3] axis) nothrow {
  if (axis.magnitude == 0.0f) return( Quaternion.init);
  axis.normalize();
  axis = axis.vMul(sin(angle.radian));
  T[4] result = [axis.x, axis.y, axis.z, cos(angle.radian)];
  return(result.normalize());
}

/** Quaternion to Matrix */
@nogc pure Matrix toMatrix(T)(T[4] v) nothrow {
  return(Matrix(
  [1 - 2 * v.y * v.y - 2 * v.z * v.z, 2 * v.x * v.y - 2 * v.z * v.w, 2 * v.x * v.z + 2 * v.y * v.w, 0,
   2 * v.x * v.y + 2 * v.z * v.w, 1 - 2 * v.x * v.x - 2 * v.z * v.z, 2 * v.y * v.z - 2 * v.x * v.w, 0,
   2 * v.x * v.z - 2 * v.y * v.w, 2 * v.y * v.z + 2 * v.x * v.w, 1 - 2 * v.x * v.x - 2 * v.y * v.y, 0,
   0, 0, 0, 1 
  ]));
}

/** Positional shortcut .w for Quaternion */
@nogc pure T w(T)(const T[] v) nothrow { assert(v.length > 3); return(v[3]); }
/** Positional shortcut .alpha for Quaternion */
@nogc pure T alpha(T)(const T[] v) nothrow { assert(v.length > 3); return(v[3]); }

/** T[4] math pass through vectorized functions for +,-,*,^
 * vAdd: a + v(1) | v(1) + v(2)
 * vMul, vDiv, vPow: b * v(1), b / v(1), v(1) * v(1) */
@nogc pure T[4] vAdd(T)(const T[4] v1, const T[4] v2) nothrow {
  T[4] vAdd = v1[] + v2[]; return(vAdd);
}
@nogc pure T[4] vAdd(T)(const T[4] v1, const T a) nothrow {
  T[4] vAdd = v1[] + a; return(vAdd);
}
@nogc pure T[4] vSub(T)(const T[4] v1, const T[4] v2) nothrow {
  T[4] vSub = v1[] - v2[]; return(vSub);
}
@nogc pure T[4] negate(T)(ref T[4] v) nothrow {
  v[] = -v[]; return(v);
}
@nogc pure T[4] vMul(T)(const T[4] v1, const T[4] v2) nothrow {
  T[4] vMul = v1[] * v2[]; return(vMul);
}
@nogc pure T[4] vMul(T)(const T[4] v1, const T b) nothrow {
  T[4] vMul = v1[] * b; return(vMul);
}
@nogc pure T[4] vDiv(T)(const T[4] v1, const T b) nothrow {
  T[4] vDiv = v1[] / b; return(vDiv);
}
@nogc pure T[4] vPow(T)(const T[4] v1) nothrow {
  T[4] vPow = v1[] * v1[]; return(vPow);
}
