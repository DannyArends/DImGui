/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import vector : euclidean;

/** Implementation of N abstract class - Should provide a custom isEqual function and the has function using custom isEqual */
struct PathNode {
  size_t parent = size_t.max;                                         /// Used during the search to record the parent of successor nodes
  size_t child  = size_t.max;                                         /// Used after the search for the application to view the search in reverse
  float[3] position = [0.0f, 0.0f, 0.0f];                             /// Position of the node
  float cost = 1.0f;                                                  /// cost of the node
  float g;                                                            /// cost of this node + it's predecessors
  float h;                                                            /// heuristic estimate of distance to goal
  @nogc @property float f() nothrow const { return(g + h); }          /// sum of cumulative cost of this node + predecessors + heuristic
  @nogc @property float x() nothrow const { return(position[0]); }
  @nogc @property float y() nothrow const { return(position[1]); }
  @nogc @property float z() nothrow const { return(position[2]); }
}

/** isEqual is just based on euclidean proximity, when the euclidean distance < 0.10f then 2 nodes equal */
bool isEqual(N)(const N x, const N y) { return(euclidean(x.position, y.position) < 0.10f); }

/** Uses the isEqual function to determine the index of a node is in the open / closed list when not found returns size_t.max */
size_t has(N)(size_t[] indices, N[] pool, N x) {
  foreach (size_t i, size_t idx; indices) { if(pool[idx].isEqual(x)) return i; }
  return size_t.max;
}
