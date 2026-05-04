/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import search : performSearch, atGoal, stepThroughPath;

struct PathRequest {
  uint dwarfUID;
  int[3] fromTile;
  int[3] goalTile;
}

struct PathResult {
  uint dwarfUID;
  float[3][] path;
  bool success;
}

PathResult pathfindWorker(immutable(WorldData) wd, PathRequest req) {
  float[3] start = wd.tileToWorld(req.fromTile);
  float[3] goal  = wd.tileToWorld(req.goalTile);
  auto result = performSearch!(WorldData, PathNode)(start, goal, cast(WorldData)wd, false);
  if(result.state == SearchState.FAILED || result.state == SearchState.INVALID) return PathResult(req.dwarfUID, [], false);
  float[3][] path;
  while(result.pathptr != size_t.max && !result.atGoal()) path ~= result.stepThroughPath(false);
  path ~= result.pool[result.goal].position;
  return PathResult(req.dwarfUID, path, true);
}

/** Pathfind object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, path */
void pathfindTo(T)(ref App app, ref T obj, int[3] goalTile) {
  app.world.pendingPaths = app.world.pendingPaths.filter!(r => r.dwarfUID != obj.uid).array;  // Remove any existing pending request for this dwarf
  auto req = PathRequest(obj.uid, obj.tile, goalTile);
  foreach(tid; app.concurrency.workers.keys) {
    if(!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, req);
      obj.state = DwarfState.WaitingForPath;
      return;
    }
  }
  app.world.pendingPaths ~= req;
  obj.state = DwarfState.WaitingForPath;
}

/** Dispatch pending path finding jobs */
void dispatchPendingPaths(ref App app) {
  if(app.concurrency.paths.length > 0) return;
  foreach(tid; app.concurrency.workers.keys) {
    if(app.world.pendingPaths.length == 0) break;
    if(!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, app.world.pendingPaths[0]);
      app.world.pendingPaths = app.world.pendingPaths[1..$];
    }
  }
}
