/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

/** D-formatted C string. One home for the per-frame toStringz allocation */
const(char)* cstr(A...)(string fmt, A a) { return toStringz(format(fmt, a)); }

/** Report numbers for humans */
string humanCount(size_t n) {
  if (n >= 1_000_000_000) return format("%.1fG", n / 1_000_000_000.0);
  if (n >= 1_000_000) return format("%.1fM", n / 1_000_000.0);
  if (n >= 1_000) return format("%.1fK", n / 1_000.0);
  return format("%d", n);
}

/** Linear Interpolation (LERP) */
@nogc pure float lerp(float a, float b, float t) nothrow { return a + t * (b - a); }

/** Floor division (rounds toward -inf) — negative-safe chunk coordinates. */
@nogc pure int iDiv(int a, int b) nothrow { return((a >= 0) ? a/b : -((-a + b - 1)/b)); }

/** Round v up to a power of two within [lo, hi]; lo/hi are assumed pow2 (512..4096). */
@nogc uint clampPow2(uint v, uint lo, uint hi) nothrow pure {
  if(v <= lo){ return lo; }
  if(v >= hi){ return hi; }
  return 1u << (bsr(v - 1) + 1);
}

/** Assoc Array lazy-fallback (compute-the-default-only-on-miss) */
V getOrElse(V, K)(const V[K] map, K key, lazy V fallback) { if(auto p = key in map) return *p; return fallback; }

/** Reduce a GC slice's length. */
void shrink(T)(ref T[] a, size_t n) { a.length = n; }

/** Swap the last element into 'index', drop the last; returns the vacated index, or size_t.max if index was last/out of range. */
size_t removeAt(C)(ref C c, size_t index) {
  if(index >= c.length) return(size_t.max);
  size_t last = c.length - 1;
  if(index != last) c[index] = c[last];
  c.shrink(last);
  return((index != last) ? last : size_t.max);
}

/** Swap-remove for instanced managers: pops the entry and its instance row in lockstep. */
mixin template SwapRemove(alias arr) {
  void remove(size_t index) { arr.removeAt(index); instances.removeAt(index); }
}
