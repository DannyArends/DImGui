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

unittest {
  // SparseSet: add/contains/length, dedup, capacity bound
  SparseSet s;
  s.init(16);
  assert(s.length == 0 && s.capacity == 16);
  s.add(3); s.add(7); s.add(3);             // duplicate add is a no-op
  assert(s.length == 2);
  assert(3 in s && 7 in s);
  assert(!(5 in s));
  assert(!(100 in s));                      // out of domain -> not contained, no crash
  assert(!(-1 in s));                       // negative -> not contained

  // SparseSet: swap-with-last remove keeps the moved key consistent
  s.clear();
  s.add(1); s.add(2); s.add(3); s.add(4);   // dense = [1,2,3,4]
  s.remove(2);                              // removes middle; last (4) swaps into its slot
  assert(s.length == 3);
  assert(!(2 in s));                        // removed
  assert(1 in s && 3 in s && 4 in s);       // moved key 4 still findable (slot fixed)
  s.remove(999 & 0);                        // remove key 0 (absent) -> no-op
  assert(s.length == 3);

  // SparseSet: opOpAssign ~= routes to add, keys view reflects contents
  s.clear();
  s ~= 5; s ~= 8;
  assert(s.length == 2 && 5 in s && 8 in s);
  import std.algorithm : sort;
  auto ks = s.keys.dup.sort.array;
  assert(ks == [5, 8]);

  // SparseSet: clear resets to empty but preserves capacity
  s.clear();
  assert(s.length == 0 && s.capacity == 16 && !(5 in s));
}
