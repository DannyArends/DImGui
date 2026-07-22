/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Sparse set of non-negative int keys in [0, capacity). O(1) add / remove / contains, dense contiguous iteration, no hashing.
    `dense` holds present keys; `slot[key]` is the key's index in `dense` (-1 = absent). Private and mutated together, so they cannot desync. */
struct SparseSet {
  private PackedArray!int dense;        /// packed present keys (grow-only, non-GC append)
  private int[] slot;                   /// key -> index in dense, or -1

  void init(size_t capacity) {
    slot.length = capacity;
    slot[] = -1;
    dense.reset();
  }

  void add(int key) {
    if(slot[key] != -1) return;
    slot[key] = cast(int)dense.length;
    dense ~= key;
  }

  void remove(int key) {
    int p = slot[key];
    if(p == -1) return;
    int moved = dense[dense.length - 1];
    dense.removeAt(p);
    slot[moved] = p;
    slot[key] = -1;
  }

  void clear() { foreach(k; dense.items) slot[k] = -1; dense.reset(); }

  ref SparseSet opOpAssign(string op : "~")(int key) { add(key); return this; }
  @nogc bool opBinaryRight(string op : "in")(int key) const nothrow { return contains(key); }
  @nogc bool contains(int key) const nothrow { return key >= 0 && key < slot.length && slot[key] != -1; }
  @nogc @property size_t length() const nothrow { return dense.length; }
  @nogc @property size_t capacity() const nothrow { return slot.length; }

  /** Iterate / index as the dense int[] of present keys (read view). */
  alias keys this;
  @property inout(int)[] keys() inout nothrow { return dense.items; }
}
