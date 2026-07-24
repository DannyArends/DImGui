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
