/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import packedarray : PackedArray;

/** Sparse set of non-negative int keys in [0, capacity): O(1) add/remove/contains, dense hash-free iteration */
struct SparseSet {
  private PackedArray!int dense;        /// packed present keys (grow-only, non-GC append)
  private int[] slot;                   /// key -> index in dense, or -1

  /** Read view: the set's present keys (SparseSet's term for the composed PackedArray's items) */
  @property inout(int)[] keys() inout nothrow { return dense.items; }
  alias keys this;

  /** Size the key domain to [0, capacity); all keys start absent, dense cleared */
  void init(size_t capacity) {
    slot.length = capacity;
    slot[] = -1;
    dense.reset();
  }

  /** O(1) add; no-op if the key is already present */
  void add(int key) {
    if(slot[key] != -1) return;
    slot[key] = cast(int)dense.length;
    dense ~= key;
  }

  /** O(1) remove via swap-with-last; no-op if the key is absent */
  void remove(int key) {
    int p = slot[key]; if(p == -1) return;
    slot[key] = -1;
    if(dense.removeAt(p) != size_t.max) { slot[dense[p]] = p; }
  }

  /** Remove all keys but keep capacity */
  void clear() { foreach(k; dense.items) slot[k] = -1; dense.reset(); }

  /** s ~= key -> O(1) add (intercepts ~= so it never falls through the alias to the raw slice) */
  ref SparseSet opOpAssign(string op : "~")(int key) { add(key); return this; }

  /** key in s -> O(1) membership test */
  @nogc bool opBinaryRight(string op : "in")(int key) const nothrow { return contains(key); }

  /** True if key is within the domain and currently present */
  @nogc bool contains(int key) const nothrow { return key >= 0 && key < slot.length && slot[key] != -1; }

  /** Number of present keys */
  @nogc @property size_t length() const nothrow { return dense.length; }

  /** Size of the key domain (max capacity of distinct keys) */
  @nogc @property size_t capacity() const nothrow { return slot.length; }
}

