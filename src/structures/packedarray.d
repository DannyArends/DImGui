/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

/** Growable dense array with separate live-count and capacity; grow-only, non-GC append after warmup */
struct PackedArray(T) {
  private T[] store = [];               /// backing block (capacity); never shrinks
  private size_t w = 0;                 /// live element count

  /** Live view of written elements [0..w), never the backing capacity; aliased so the struct reads as this slice */
  @property inout(T)[] items() inout nothrow @nogc { return store[0 .. w]; }
  alias items this;

  /** Ensure capacity for at least n elements, growing geometrically (only grows) */
  void reserve(size_t n, size_t initial = 128, size_t factor = 2) nothrow {
    if(n <= store.length) return;
    size_t cap = store.length == 0 ? initial : store.length;
    while(cap < n){ cap *= factor; }
    store.length = cap;
    store.assumeSafeAppend();
  }

  /** Clear the live count but keep capacity, so a following rebuild reuses the backing memory */
  @nogc void reset() nothrow { w = 0; }

  /** Append one element, growing capacity only when needed */
  void opOpAssign(string op : "~")(T v) nothrow { reserve(w + 1); store.ptr[w++] = v; }

  /** Append a slice of elements in one block copy, growing capacity once */
  void opOpAssign(string op : "~")(const(T)[] vs) nothrow {
    if(vs.length == 0) return;
    reserve(w + vs.length);
    store.ptr[w .. w + vs.length] = vs[];
    w += vs.length;
  }

  /** Adopt an existing slice as the contents (count and backing become rhs) */
  void opAssign(T[] rhs) { store = rhs; w = rhs.length; }

  /** Set the live count to n, growing capacity if needed */
  void resize(size_t n) nothrow { reserve(n); w = n; }

  /** Reduce the live count without touching capacity (grow-only backing preserved). */
  @nogc void shrink(size_t n) nothrow { w = n; }

  /** Reference to the element at index i (no bounds check) */
  @nogc ref inout(T) opIndex(size_t i) inout nothrow { return store.ptr[i]; }

  /** Number of live elements */
  @nogc @property size_t length() const nothrow { return w; }

  /** Backing capacity (allocated slots, may exceed length) */
  @nogc @property size_t reserved() const nothrow { return store.length; }
}

