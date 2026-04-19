/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/// Deterministic hash of 3D integer coords -> float [0..1]
@nogc pure float valueNoise(int x, int y, int z, int seed = 0) nothrow {
  int n = x + y * 57 + z * 131 + seed * 1013;
  n = (n << 13) ^ n;
  return (1.0f - ((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 1073741824.0f) * 0.5f + 0.5f;
}

@nogc pure float lerp(float a, float b, float t) nothrow { return a + t * (b - a); }

/// Smooth noise at float coords (trilinear interpolated)
@nogc pure float smoothNoise(float x, float y, float z, int seed = 0) nothrow {
  int ix = cast(int)floor(x); float fx = x - ix;
  int iy = cast(int)floor(y); float fy = y - iy;
  int iz = cast(int)floor(z); float fz = z - iz;
  float ux = fx * fx * (3.0f - 2.0f * fx);
  float uy = fy * fy * (3.0f - 2.0f * fy);
  float uz = fz * fz * (3.0f - 2.0f * fz);
  return lerp(
    lerp(lerp(valueNoise(ix,   iy,   iz,   seed), valueNoise(ix+1, iy,   iz,   seed), ux),
         lerp(valueNoise(ix,   iy+1, iz,   seed), valueNoise(ix+1, iy+1, iz,   seed), ux), uy),
    lerp(lerp(valueNoise(ix,   iy,   iz+1, seed), valueNoise(ix+1, iy,   iz+1, seed), ux),
         lerp(valueNoise(ix,   iy+1, iz+1, seed), valueNoise(ix+1, iy+1, iz+1, seed), ux), uy),
    uz);
}

/// Multi-octave fractal noise
@nogc pure float fbm(float x, float y, float z, int octaves = 6, float lacunarity = 2.0f, float gain = 0.5f, int seed = 0) nothrow {
  float value = 0.0f, amplitude = 0.5f, frequency = 1.0f;
  for (int i = 0; i < octaves; i++) {
    value += amplitude * smoothNoise(x * frequency, y * frequency, z * frequency, seed + i);
    amplitude *= gain;
    frequency *= lacunarity;
  }
  return(clamp(value, 0.0f, 1.0f));
}

enum float NOISE_SCALE = 0.02f;

@nogc pure float[2] noiseHT(int x, int z, const int[2] seed) nothrow {
  return [fbm(x * NOISE_SCALE, z * NOISE_SCALE, 0.0f, 4, 2.0f, 0.5f, seed[0]), fbm(x * NOISE_SCALE, z * NOISE_SCALE, 0.0f, 4, 2.0f, 0.5f, seed[1])];
}

