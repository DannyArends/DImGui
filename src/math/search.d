/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import searchnode : PathNode, isEqual, has;
import vector : euclidean;

enum SearchState { NOT_INITIALISED = 0, SEARCHING = 1, SUCCEEDED = 2, FAILED = 3, INVALID = 4 };

/** Implementation of the search state structure */
struct Search(M, N) {
  M map;                                                    /// map information structure
  size_t start = size_t.max;                                /// index into pool: Start Node
  size_t goal  = size_t.max;                                /// index into pool: Goal node
  size_t pathptr = size_t.max;                              /// index into pool: pointer to the current node in the path
  N[] pool;                                                 /// stable node storage
  size_t[] openlist;                                        /// Astar open list: indices into pool
  size_t[float[3]] closedset;                               /// Astar closed list: indices into pool
  SearchState state = SearchState.NOT_INITIALISED;          /// Astar SearchState
  size_t steps = 0;                                         /// search steps taken
  size_t path = 0;                                          /// step in current path
  size_t maxsteps = 1500;                                   /// maximum number of search steps
  bool cancel = false;                                      /// cancels an active search
}

/** Set the start and goal node and set the state to searching */
void setStartAndGoalStates(S, M, N)(ref S search, ref M map, ref N startnode, ref N goalnode) {
  search.map = map;

  startnode.g = 0.0f;
  startnode.h = euclidean(startnode.position, goalnode.position);
  startnode.parent = size_t.max;

  search.pool ~= startnode;
  search.start = search.pool.length - 1;
  search.pool ~= goalnode;
  search.goal = search.pool.length - 1;

  search.state = SearchState.SEARCHING;
  search.openlist ~= search.start;
  search.pathptr = search.start;
  search.steps = 0;

  // If the start and end are the same the search requested is not valid
  if (startnode.isEqual(goalnode)) search.state = SearchState.INVALID;
}

/** Walk backwards via the parent pointers, setting the child pointers */
void storeRoute(S)(ref S search, size_t nodeIdx) {
  size_t nodeChild = nodeIdx;
  size_t nodeParent = search.pool[nodeChild].parent;
  while(nodeParent != size_t.max && nodeChild != search.start) {
    search.pool[nodeParent].child = nodeChild;
    nodeChild = nodeParent;
    nodeParent = search.pool[nodeChild].parent;
  }
  search.start = nodeChild;
  search.pathptr = search.start;
}

/** Do a step of the A star searching algorithm */
SearchState step(alias getSuccessors, S)(ref S search) {
  if(search.state != SearchState.SEARCHING) return search.state;
  if(search.openlist.empty() || search.cancel) { search.state = SearchState.FAILED; return search.state; }

  size_t nIdx = search.openlist[0];
  search.steps++;

  if(search.pool[nIdx].isEqual(search.pool[search.goal])) {
    search.state = SearchState.SUCCEEDED;
    search.pool[search.goal].parent = search.pool[nIdx].parent;
    search.storeRoute(search.goal);
    return search.state;
  }

  auto successors = getSuccessors(search.map, search.pool[nIdx]);
  if (successors.empty()) {
    search.closedset[search.pool[nIdx].position] = nIdx;
    search.openlist = search.openlist.remove(0);
    return search.state;
  }

  foreach (ref s; successors) {
    float newG = search.pool[nIdx].g + s.cost;
    size_t i;
    if ((i = search.openlist.has(search.pool, s)) != size_t.max && search.pool[search.openlist[i]].g <= newG) continue;
    if (auto c = s.position in search.closedset) { if(search.pool[*c].g <= newG) continue; search.closedset.remove(s.position); }
    s.parent = nIdx;
    s.g = newG;
    s.h = euclidean(s.position, search.pool[search.goal].position);
    if(s.isEqual(search.pool[search.goal])) { // accept on generation
      search.pool[search.goal].parent = nIdx;
      search.state = SearchState.SUCCEEDED;
      search.storeRoute(search.goal);
      return search.state;
    }
    if((i = search.openlist.has(search.pool, s)) != size_t.max) {
      search.pool[search.openlist[i]] = s;
    } else {
      search.pool ~= s;
      search.openlist ~= search.pool.length - 1;
    }
  }

  search.closedset[search.pool[nIdx].position] = nIdx;
  search.openlist = search.openlist.remove(0);
  search.openlist.sort!((a, b) => search.pool[a].f < search.pool[b].f);
  return search.state;
}

/** Take a step through the path computed */
float[3] stepThroughPath(S)(ref S search, bool verbose = true) {
  if (search.pathptr == size_t.max) return cast(float[3])[0.0f, 0.0f, 0.0f];
  float[3] p = search.pool[search.pathptr].position;
  if (verbose) SDL_Log("path %d : [%.2f, %.2f, %.2f]\n", search.path, p[0], p[1], p[2]);
  search.pathptr = search.pool[search.pathptr].child;
  search.path++;
  return p;
}

/** Test if the current path pointer is at the goal position */
bool atGoal(S)(const S search) {
  if(search.pathptr == size_t.max) return(true);
  return(search.pool[search.pathptr].isEqual(search.pool[search.goal]));
}

/** Perform a search and return the result, after which the search.stepThroughPath allows to walk it */
Search!(M, N) performSearch(M, N, alias getSuccessors)(float[3] start = [0.0f, -4.0f, 0.0f], float[3] goal = [-3.0f, 2.0f, -3.2f], M map, bool verbose = true) {
  Search!(M, PathNode) search;
  PathNode s = PathNode(position: start);
  PathNode g = PathNode(position: goal);
  search.setStartAndGoalStates(map, s, g);
  do{
    search.state = step!getSuccessors(search);
  }while(search.state == SearchState.SEARCHING && search.steps < search.maxsteps);

  if (search.state == SearchState.SEARCHING && search.openlist.length > 0) {
    search.goal = search.openlist[0];
    search.storeRoute(search.openlist[0]);
  }
  return search;
}

