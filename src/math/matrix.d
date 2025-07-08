/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;

import vector : dot, sum, x, y, z, magnitude, xyz, vSub, cross, normalize;
import quaternion : xyzw, vMul;

/** Matrix is a [4x4] 'structure' stored as float[16] (defaults to identity matrix).
 */
struct Matrix {
    float[16] data = [
      1.0f, 0.0f, 0.0f, 0.0f,
      0.0f, 1.0f, 0.0f, 0.0f,
      0.0f, 0.0f, 1.0f, 0.0f,
      0.0f, 0.0f, 0.0f, 1.0f ];
  alias data this;
}

alias Matrix mat4;

/** Convert from row-based aiMatrix to our column-based Matrix type
 */
Matrix toMatrix(aiMatrix4x4 m){
  float[16] myMatrixArray = [
    m.a1, m.b1, m.c1, m.d1,
    m.a2, m.b2, m.c2, m.d2,
    m.a3, m.b3, m.c3, m.d3,
    m.a4, m.b4, m.c4, m.d4
  ];
  return(Matrix(myMatrixArray));
}

/** Radian to degree, -180 .. 0 .. 180 */
@nogc pure float degree(float rad) nothrow { return rad * (180.0f / PI); }

/** Degree to radian, -180 .. 0 .. 180 */
@nogc pure float radian(float deg) nothrow {return deg * (PI / 180.0f); }

/** Matrix x Matrix */
@nogc pure Matrix multiply(const Matrix m1, const Matrix m2) nothrow {
  Matrix res;
  for (size_t col = 0; col < 4; ++col) {
    for (size_t row = 0; row < 4; ++row) {
      float sum = 0.0f;
      for (size_t k = 0; k < 4; ++k) {
        sum += m1[k * 4 + row] * m2[col * 4 + k];
      }
      res[col * 4 + row] = sum;
    }
  }
  return res;
}

/** Matrix x V3 */
@nogc pure float[3] multiply(const Matrix m, const float[3] v) nothrow {
  return(m.multiply(v.xyzw()).xyz());
}

/** Matrix x V4 */
@nogc pure float[4] multiply(const Matrix m, const float[4] v) nothrow {
  float[4] res;
  for (size_t i = 0; i < 4; ++i) {
    res[i] = v.vMul([ m[i + 0], m[i + 4], m[i + 8], m[i + 12] ]).sum();
  }
  return res;
}

/** Matrix x Yaw, Pitch, Roll vector in degrees V(yaw, pitch, roll) - Applies rotations in local object space (Yaw -> Pitch -> Roll) */
@nogc pure Matrix rotate(const Matrix m, const float[3] v) nothrow {
  return m.multiply(rotate(v));
}

@nogc pure Matrix rotate(const float[3] v) nothrow {
  float yaw   = radian(v[0]); float pitch = radian(v[1]); float roll  = radian(v[2]);

  Matrix rotateYaw = Matrix([
      cos(yaw), 0.0f, sin(yaw), 0.0f,
      0.0f,     1.0f, 0.0f,     0.0f,
     -sin(yaw), 0.0f, cos(yaw), 0.0f,
      0.0f,     0.0f, 0.0f,     1.0f
  ]);

  Matrix rotatePitch = Matrix([
      cos(pitch), -sin(pitch), 0.0f, 0.0f,
      sin(pitch),  cos(pitch), 0.0f, 0.0f,
      0.0f,        0.0f,       1.0f, 0.0f,
      0.0f,        0.0f,       0.0f, 1.0f
  ]);

  Matrix rotateRoll = Matrix([
      1.0f, 0.0f,       0.0f,      0.0f,
      0.0f, cos(roll), -sin(roll), 0.0f,
      0.0f, sin(roll),  cos(roll), 0.0f,
      0.0f, 0.0f,       0.0f,      1.0f
  ]);

  // Apply rotations in the order: Roll -> Pitch -> Yaw (local axes)
  return(rotateRoll.multiply(rotatePitch).multiply(rotateYaw));
}

/** Scale from a matrix M */
float[3] scale(const Matrix m) {
  float[3] s = [
    magnitude([m[0], m[1], m[2]]),
    magnitude([m[4], m[5], m[6]]),
    magnitude([m[8], m[9], m[10]])
  ];
  return(s);
}

@nogc pure Matrix scale(const Matrix m, const float[3] v) nothrow {
  return(multiply(m, scale(v)));
}

@nogc pure Matrix scale(const float[3] v) nothrow {
  Matrix scale;
  scale[0] = v[0]; scale[5] = v[1]; scale[10] = v[2];
  return(scale);
}

/** Matrix x Translation V(x, y, z) */
@nogc pure Matrix translate(const Matrix m, const float[3] v) nothrow {
  return(multiply(m, translate(v)));
}

/** Translation V(x, y, z) */
@nogc pure Matrix translate(const float[3] v) nothrow {
  Matrix translation;
  translation[12] = v[0]; translation[13] = v[1]; translation[14] = v[2];
  return(translation);
}

/** getTranslation float[3] from a Matrix V4(l, r, b, t) */
@nogc pure float[3] position(const Matrix m) nothrow { return([m[12], m[13], m[14]]); }
@nogc pure Matrix position(ref Matrix m, const float[3] v) nothrow { 
  m[12] = v[0]; m[13] = v[1]; m[14] = v[2];
  return(m);
}

/** Orthogonal projection Matrix V4(l, r, b, t) */
@nogc pure Matrix orthogonal(float left, float right, float bottom, float top, float near, float far) nothrow {
  Matrix projection;

  projection[0]  =  2.0f / (right - left);
  projection[5]  = -2.0f / (top - bottom);
  projection[10] =  1.0f / (far - near);

  projection[12] = -(right + left) / (right - left);
  projection[13] = -(top + bottom) / (top - bottom);
  projection[14] =  -near / (far - near);

  return projection;
}

/** Perspective projection Matrix V4(f, a, n, f) */
@nogc pure Matrix perspective(float fovy, float aspectRatio, float near, float far) nothrow {
  float tanHalfFovy = tan(radian(fovy) / 2.0f);
  float x  =  1.0f / (aspectRatio * tanHalfFovy);
  float y  = -1.0f / tanHalfFovy;
  float A  = -(far + near) / (far - near);
  float B  = -2.0f * far * near / (far - near);
  return(Matrix([
        x,    0.0f,  0.0f,  0.0f,
        0.0f,    y,  0.0f,  0.0f,
        0.0f, 0.0f,     A, -1.0f,
        0.0f, 0.0f,     B,  0.0f,
    ]));
}

/** lookAt function, looks from pos at "at" using the upvector (up) */
@nogc pure Matrix lookAt(float[3] pos, float[3] at, float[3] up) nothrow {
  auto f = vSub(at, pos).normalize();
  auto s = cross(f, up).normalize();
  auto u = cross(s, f);

  return(Matrix([
        s[0], u[0], -f[0],  0.0f,
        s[1], u[1], -f[1],  0.0f,
        s[2], u[2], -f[2],  0.0f,
        -dot(s, pos),-dot(u, pos), dot(f, pos), 1.0f
    ]));
}

/** transpose a Matrix */
@nogc pure Matrix transpose(const Matrix m) nothrow {
  Matrix mt;
  for (size_t row = 0; row < 4; ++row) {
    for (size_t col = 0; col < 4; ++col) {
      mt[(col * 4) + row] = m[(row * 4) + col];
    }
  }
  return(mt);
}

/** inverse of a Matrix using the determinant */
@nogc pure Matrix inverse(const Matrix m) nothrow {
  Matrix inv;

  inv[0] = m[5]  * m[10] * m[15] - m[5]  * m[11] * m[14] - 
           m[9]  * m[6]  * m[15] + m[9]  * m[7]  * m[14] +
           m[13] * m[6]  * m[11] - m[13] * m[7]  * m[10];

  inv[4] = -m[4]  * m[10] * m[15] + m[4]  * m[11] * m[14] + 
            m[8]  * m[6]  * m[15] - m[8]  * m[7]  * m[14] - 
            m[12] * m[6]  * m[11] + m[12] * m[7]  * m[10];

  inv[8] = m[4]  * m[9] * m[15] - m[4]  * m[11] * m[13] - 
           m[8]  * m[5] * m[15] + m[8]  * m[7]  * m[13] + 
           m[12] * m[5] * m[11] - m[12] * m[7]  * m[9];

  inv[12] = -m[4]  * m[9] * m[14] + m[4]  * m[10] * m[13] +
             m[8]  * m[5] * m[14] - m[8]  * m[6]  * m[13] - 
             m[12] * m[5] * m[10] + m[12] * m[6]  * m[9];

  inv[1] = -m[1]  * m[10] * m[15] + m[1]  * m[11] * m[14] + 
            m[9]  * m[2]  * m[15] - m[9]  * m[3] * m[14] - 
            m[13] * m[2]  * m[11] + m[13] * m[3] * m[10];

  inv[5] = m[0]  * m[10] * m[15] - m[0]  * m[11] * m[14] - 
           m[8]  * m[2]  * m[15] + m[8]  * m[3] * m[14] + 
           m[12] * m[2]  * m[11] - m[12] * m[3] * m[10];

  inv[9] = -m[0]  * m[9] * m[15] + m[0]  * m[11] * m[13] + 
            m[8]  * m[1] * m[15] - m[8]  * m[3]  * m[13] - 
            m[12] * m[1] * m[11] + m[12] * m[3]  * m[9];

  inv[13] = m[0]  * m[9] * m[14] - m[0]  * m[10] * m[13] - 
            m[8]  * m[1] * m[14] + m[8]  * m[2]  * m[13] + 
            m[12] * m[1] * m[10] - m[12] * m[2]  * m[9];

  inv[2] = m[1]  * m[6] * m[15] - m[1]  * m[7] * m[14] - 
           m[5]  * m[2] * m[15] + m[5]  * m[3] * m[14] + 
           m[13] * m[2] * m[7]  - m[13] * m[3] * m[6];

  inv[6] = -m[0]  * m[6] * m[15] + m[0]  * m[7] * m[14] + 
            m[4]  * m[2] * m[15] - m[4]  * m[3] * m[14] - 
            m[12] * m[2] * m[7]  + m[12] * m[3] * m[6];

  inv[10] = m[0]  * m[5] * m[15] - m[0]  * m[7] * m[13] - 
            m[4]  * m[1] * m[15] + m[4]  * m[3] * m[13] + 
            m[12] * m[1] * m[7]  - m[12] * m[3] * m[5];

  inv[14] = -m[0]  * m[5] * m[14] + m[0]  * m[6] * m[13] + 
             m[4]  * m[1] * m[14] - m[4]  * m[2] * m[13] - 
             m[12] * m[1] * m[6]  + m[12] * m[2] * m[5];

  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + 
            m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - 
            m[9] * m[2] * m[7]  + m[9] * m[3] * m[6];

  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - 
           m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + 
           m[8] * m[2] * m[7]  - m[8] * m[3] * m[6];

  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + 
             m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - 
             m[8] * m[1] * m[7]  + m[8] * m[3] * m[5];

  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - 
            m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + 
            m[8] * m[1] * m[6]  - m[8] * m[2] * m[5];

  float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];

  if (det == 0) return Matrix();
  det = 1.0f / det;
  inv[] = inv[] * det;
  return inv;
}

