/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import vector : x,y,z, magnitude, normalize, vMul, sum;
import matrix : radian;

/** Quaternion, stored as float[4]
 */
struct Quaternion { 
  float[4] data = [ 0.0f, 0.0f, 0.0f, 1.0f ];
  alias data this;
}

/** Quaternion multiplication */
@nogc pure float[4] qMul(const float[4] a, const float[4] b) nothrow {
  return [
    a[3]*b[0] + a[0]*b[3] + a[1]*b[2] - a[2]*b[1],
    a[3]*b[1] - a[0]*b[2] + a[1]*b[3] + a[2]*b[0],
    a[3]*b[2] + a[0]*b[1] - a[1]*b[0] + a[2]*b[3],
    a[3]*b[3] - a[0]*b[0] - a[1]*b[1] - a[2]*b[2]
  ];
}

/** Returns the normalized vector of v */
@nogc pure T[4] normalize(T)(T[4] v) nothrow {
  float sqr = v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + v[3] * v[3];
  if(sqr == 0) return(v);
  if(abs(sqr - 1.0f) < 1e-6f) return(v);
  float invrt = 1.0f / sqrt(sqr);
  v[] *= invrt;
  return(v);
}

/** Create a T[3], w as a T[4] */
@nogc pure T[4] xyzw(T)(const T[3] v, T w = 1.0f) nothrow { return([v.x, v.y, v.z, w]); }

/** Create a T[3], alpha as a T[4] */
@nogc pure T[4] rgba(T)(const T[3] v, T a = 1.0f) nothrow { return([v.red, v.green, v.blue, a]); }

/** Dot product between v1 and v2 */
@nogc pure T dot(T)(const T[4] v1, const T[4] v2) nothrow { T[4] vDot = v1[] * v2[]; return(sum(vDot)); }

T[4] slerp(T)(const T[4] start, const T[4] end, float factor) {
  T[4] result;
  T[4] e = end;
  float dot = dot(start, e);
  if (dot < 0.0f) {    // Ensure the shortest path
    e[] = -e[];
    dot = -dot;
  }

  const float DOT_THRESHOLD = 0.9995f;
  if (dot > DOT_THRESHOLD) {
    // If the quaternions are very close, just linear interpolate (L.I.)
    result[] = start[] + factor * (e[] -start[]);
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

  result[] = start.vMul(s0)[] + e.vMul(s1)[];
  return result;
}

@nogc pure Matrix rotate(const float[4] q) nothrow {
  float x = q[0], y = q[1], z = q[2], w = q[3];
  float x2 = x+x, y2 = y+y, z2 = z+z;
  float xx = x*x2, xy = x*y2, xz = x*z2;
  float yy = y*y2, yz = y*z2, zz = z*z2;
  float wx = w*x2, wy = w*y2, wz = w*z2;
  return Matrix([1-(yy+zz), xy+wz,   xz-wy,   0,
                 xy-wz,   1-(xx+zz), yz+wx,   0,
                 xz+wy,   yz-wx,   1-(xx+yy), 0,
                 0,       0,       0,         1]);
}

/** angleAxis */
@nogc pure T[4] angleAxis(T)(T angle, T[3] axis) nothrow {
  float sqr = axis[0]*axis[0] + axis[1]*axis[1] + axis[2]*axis[2];
  if (sqr == 0.0f) return(Quaternion.init);
  axis[] *= 1.0f / sqrt(sqr);
  float halfRad = angle.radian / 2.0f;
  axis = axis.vMul(sin(halfRad));
  T[4] result = [axis.x, axis.y, axis.z, cos(halfRad)];
  return(result.normalize());
}

/** Positional shortcut .w for Quaternion */
@nogc pure T w(T)(const T[] v) nothrow { assert(v.length > 3); return(v[3]); }
/** Positional shortcut .alpha for Quaternion */
@nogc pure T alpha(T)(const T[] v) nothrow { assert(v.length > 3); return(v[3]); }

/** T[4] math pass through vectorized functions for +,-,*,^
 * vAdd: a + v(1) | v(1) + v(2)
 * vMul, vDiv, vPow: b * v(1), b / v(1), v(1) * v(1) */
@nogc pure T[4] vAdd(T)(const T[4] v1, const T[4] v2) nothrow { T[4] vAdd = v1[] + v2[]; return(vAdd); }
@nogc pure T[4] vAdd(T)(const T[4] v1, const T a) nothrow { T[4] vAdd = v1[] + a; return(vAdd); }
@nogc pure T[4] vSub(T)(const T[4] v1, const T[4] v2) nothrow { T[4] vSub = v1[] - v2[]; return(vSub); }
@nogc pure T[4] negate(T)(ref T[4] v) nothrow { v[] = -v[]; return(v); }
@nogc pure T[4] vMul(T)(const T[4] v1, const T[4] v2) nothrow { T[4] vMul = v1[] * v2[]; return(vMul); }
@nogc pure T[4] vMul(T)(const T[4] v1, const T b) nothrow { T[4] vMul = v1[] * b; return(vMul); }
@nogc pure T[4] vDiv(T)(const T[4] v1, const T b) nothrow { T[4] vDiv = v1[] / b; return(vDiv); }
@nogc pure T[4] vPow(T)(const T[4] v1) nothrow { T[4] vPow = v1[] * v1[]; return(vPow); }
