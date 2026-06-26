/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

/** Sparse set of non-negative int keys in [0, capacity).
    O(1) add / remove / contains, dense contiguous iteration, no hashing.
    `dense` holds present keys; `slot[key]` is the key's index in `dense` (-1 = absent).
    Both arrays are private and only mutated together, so they cannot desync. */
struct SparseSet {
  private int[] dense;                  /// packed list of present keys
  private int[] slot;                   /// key -> index in `dense`, or -1

  /** Size the key domain to [0, capacity); all keys start absent. */
  void init(size_t capacity) {
    slot.length = capacity;
    slot[] = -1;
    dense.length = 0;
    dense.assumeSafeAppend();
  }

  /** O(1) add; no-op if already present. */
  void add(int key) {
    if(slot[key] != -1) return;
    slot[key] = cast(int)dense.length;
    dense ~= key;
  }

  /** O(1) remove via swap-with-last; no-op if absent. */
  void remove(int key) {
    int p = slot[key];
    if(p == -1) return;
    int last = cast(int)dense.length - 1;
    int moved = dense[last];
    dense[p] = moved;
    slot[moved] = p;
    dense.length = last;
    slot[key] = -1;
  }

  /** Remove all keys, keep capacity. */
  void clear() {
    foreach(k; dense) slot[k] = -1;
    dense.length = 0;
    dense.assumeSafeAppend();
  }

  /** s ~= key  →  O(1) add (intercepts ~= so it never falls through alias to the raw slice). */
  ref SparseSet opOpAssign(string op : "~")(int key) { add(key); return this; }

  /** key in s  →  O(1) membership. */
  @nogc bool opBinaryRight(string op : "in")(int key) const nothrow { return contains(key); }

  @nogc bool contains(int key) const nothrow { return key >= 0 && key < slot.length && slot[key] != -1; }
  @nogc @property size_t length() const nothrow { return dense.length; }
  @nogc @property size_t capacity() const nothrow { return slot.length; }

  /** Iterate / index as the dense int[] of present keys (read view). */
  alias keys this;
  @property inout(int)[] keys() inout nothrow { return dense; }
}
