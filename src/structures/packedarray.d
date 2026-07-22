/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

/** Growable dense array with separate live-count and capacity */
struct PackedArray(T) {
  private T[] store = [];
  private size_t w = 0;

  /** Live view: only the elements actually written, not the backing capacity. */
  @property inout(T)[] items() inout nothrow @nogc { return store[0 .. w]; }
  alias items this;

  /** Ensure capacity for at least `n` elements, growing geometrically. Capacity only grows. */
  void reserve(size_t n, size_t initial = 128, size_t factor = 2) nothrow {
    if(n <= store.length) return;
    size_t cap = store.length == 0 ? initial : store.length;
    while(cap < n){ cap *= factor; }
    store.length = cap;
    store.assumeSafeAppend();
  }

  @nogc void reset() nothrow { w = 0; }                       /// clear count, keep capacity
  void opOpAssign(string op : "~")(T v) nothrow { reserve(w + 1); store.ptr[w++] = v; }
  void opOpAssign(string op : "~")(const(T)[] vs) nothrow {
    if(vs.length == 0) return;
    reserve(w + vs.length);
    store.ptr[w .. w + vs.length] = vs[];
    w += vs.length;
  }
  void opAssign(T[] rhs) { store = rhs; w = rhs.length; }     /// adopt an existing slice as contents
  void resize(size_t n) nothrow { reserve(n); w = n; }        /// set live count (grows capacity if needed)

  /** Swap-and-pop: move the last live element into slot i, drop the last. O(1), no order. */
  @nogc void removeAt(size_t i) nothrow { if(w == 0 || i >= w) return; if(i != w - 1) store.ptr[i] = store.ptr[w - 1]; w--; }

  @nogc ref inout(T) opIndex(size_t i) inout nothrow { return store.ptr[i]; }
  @nogc @property size_t length() const nothrow { return w; }
  @nogc @property size_t reserved() const nothrow { return store.length; }   /// backing capacity
}
