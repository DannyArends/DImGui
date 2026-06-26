/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

enum float NOISE_SCALE = 0.02f;

/** Deterministic hash of N dimensional integer coords -> float [0..1] */
@nogc pure float valueNoise(int N)(int[N] c, int seed = 0) nothrow {
  static immutable int[4] primes = [1, 57, 131, 1009];
  int n = seed * 1013;
  static foreach (d; 0 .. N) { n += c[d] * primes[d]; }
  n = (n << 13) ^ n;
  return (1.0f - ((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 1073741824.0f) * 0.5f + 0.5f;
}

@nogc pure float lerp(float a, float b, float t) nothrow { return a + t * (b - a); }

/** Smooth noise at N dimensional float coords (trilinear interpolated) */
@nogc pure float smoothNoise(int N = 3)(float[N] p, int seed = 0) nothrow {
  int[N] ip;
  float[N] u;
  static foreach (d; 0 .. N) {{
    ip[d] = cast(int)floor(p[d]);
    float f = p[d] - ip[d];
    u[d] = f * f * (3.0f - 2.0f * f);
  }}
  float result = 0.0f;
  static foreach (corner; 0 .. (1 << N)) {{
    float weight = 1.0f;
    int[N] c;
    static foreach (d; 0 .. N) {{
      enum bit = (corner >> d) & 1;
      c[d] = ip[d] + bit;
      weight *= bit ? u[d] : (1.0f - u[d]);
    }}
    result += weight * valueNoise(c, seed);
  }}
  return result;
}

/** Multi-octave fractal noise */
@nogc pure float fbm(int N = 3)(float[N] p, int octaves = 6, float lacunarity = 2.0f, float gain = 0.5f, int seed = 0) nothrow {
  float value = 0.0f, amplitude = 0.5f, frequency = 1.0f;
  for (int i = 0; i < octaves; i++) {
    float[N] sp;
    static foreach (d; 0 .. N) { sp[d] = p[d] * frequency; }
    value += amplitude * smoothNoise!N(sp, seed + i);
    amplitude *= gain;
    frequency *= lacunarity;
  }
  return clamp(value, 0.0f, 1.0f);
}

/** Single 2D fbm value for one seed (replaces full noiseHTT in hot paths) */
@nogc pure float noise2D(int x, int z, int seed) nothrow {
  return fbm!2([x * NOISE_SCALE, z * NOISE_SCALE], 4, 2.0f, 0.5f, seed);
}

/** 3 x 2D noise */
@nogc pure float[3] noiseHTT(int x, int z, const int[3] seed) nothrow {
  float[2] p = [x * NOISE_SCALE, z * NOISE_SCALE];
  return [fbm!2(p, 4, 2.0f, 0.5f, seed[0]), fbm!2(p, 4, 2.0f, 0.5f, seed[1]), fbm!2(p, 4, 2.0f, 0.5f, seed[2])];
}

unittest {
  import std.math : isClose;

  // valueNoise is in [0,1] across a spread of coords/seeds, and deterministic
  foreach (s; 0 .. 4) { foreach (x; -20 .. 20) {
    float v = valueNoise([x, x * 3, -x], s);
    assert(v >= 0.0f && v <= 1.0f);
  } }
  assert(valueNoise([5, 9, -2], 7) == valueNoise([5, 9, -2], 7));   // pure -> identical

  // different seed (or coord) generally changes the hash
  assert(valueNoise([0, 0, 0], 0) != valueNoise([0, 0, 0], 1));
  assert(valueNoise([0, 0, 0], 0) != valueNoise([1, 0, 0], 0));

  // lerp endpoints and midpoint
  assert(lerp(2.0f, 10.0f, 0.0f) == 2.0f);
  assert(lerp(2.0f, 10.0f, 1.0f) == 10.0f);
  assert(lerp(2.0f, 10.0f, 0.5f) == 6.0f);

  // smoothNoise at integer coords collapses to valueNoise of that cell
  // (fractional part 0 -> all weight on the lower corner)
  assert(isClose(smoothNoise([3.0f, 4.0f, 5.0f], 0), valueNoise([3, 4, 5], 0)));
  assert(smoothNoise([1.5f, 2.5f, 0.0f], 0) >= 0.0f);
  assert(smoothNoise([1.5f, 2.5f, 0.0f], 0) <= 1.0f);

  // fbm stays clamped to [0,1] and is deterministic
  foreach (x; 0 .. 30) { foreach (z; 0 .. 30) {
    float h = noise2D(x, z, 42);
    assert(h >= 0.0f && h <= 1.0f);
  } }
  assert(noise2D(10, 20, 3) == noise2D(10, 20, 3));

  // noiseHTT: three independent channels; distinct seeds -> distinct values
  auto htt = noiseHTT(7, 11, [1, 2, 3]);
  foreach (c; htt) assert(c >= 0.0f && c <= 1.0f);
  assert(htt[0] != htt[1] || htt[1] != htt[2]);   // not all three identical
}