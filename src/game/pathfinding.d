/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import vector : manhattan2D;
import search : performSearch, atGoal, stepThroughPath;
import tile : getSuccessors, isStandable, isPassable, tileToWorld, worldToTile, tileAbove;

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
  auto result = performSearch!(WorldData, PathNode, getSuccessors)(start, goal, cast(WorldData)wd, false);
  if(result.state == SearchState.FAILED || result.state == SearchState.INVALID) return PathResult(req.dwarfUID, [], false);
  float[3][] path;
  while(result.pathptr != size_t.max && !result.atGoal()) path ~= result.stepThroughPath(false);
  path ~= result.pool[result.goal].position;
  return PathResult(req.dwarfUID, path, true);
}

/** Pathfind object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, path */
void pathfindTo(T)(ref GameApp app, ref T obj, int[3] goalTile) {
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
void dispatchPendingPaths(ref GameApp app) {
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

/** Invalidate any dwarf paths that pass through the given tile */
void invalidatePaths(ref GameApp app, int[3] tile) {
  if(app.world.dwarves is null) return;
  foreach(ref d; app.world.dwarves.dwarves) {
    if(!d.path.any!(p => app.world.worldToTile(p) == tile)) continue;
    d.path = [];
    d.moveTo = d.moveFrom = d.visualPos;
    d.moveT = 1.0f;
    if(d.jobStack.length > 0 && d.targetTile != noTile) app.repathTo(d, d.targetTile, d.jobStack[0].reach);
  }
}

/** Attempt to re-path object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, targetTile, path, visualPos, moveFrom, moveTo, moveT */
bool repathTo(T)(ref GameApp app, ref T obj, int[3] targetTile, Reach reach = Reach.Adjacent) {
  obj.targetTile = targetTile;
  auto goalTile = app.findGoalTile(obj, reach);
  if(goalTile == noTile) return false;
  if(obj.hasJob) obj.currentJob.goalTile = goalTile;
  if(goalTile == obj.tile) { obj.path = []; obj.state = DwarfState.Working; return true; }
  app.pathfindTo(obj, goalTile);
  return true;
}

/** Find the closest standable neighbour (air tile with solid below) to the object.
 * Requires T to have: tile, targetTile */
int[3] findGoalTile(T)(ref GameApp app, ref T obj, Reach reach = Reach.Adjacent) {
  if(reach == Reach.OnTile) return app.world.isStandable(obj.targetTile) ? obj.targetTile : noTile;

  int[3] goalTile = noTile;
  float bestScore = float.max;
  void consider(int[3] n) {
    if(!app.world.isStandable(n)) return;
    float score = manhattan2D(n, obj.tile) + app.world.data.tilePenalties.get(n, 0.0f);
    if(score < bestScore) { bestScore = score; goalTile = n; }
  }

  if(reach == Reach.AdjacentOrAbove) consider(obj.targetTile.tileAbove);   // standing on top is valid
  foreach(n; app.world.tileNeighbours(obj.targetTile)[0..2] ~ app.world.tileNeighbours(obj.targetTile)[4..6]) {
    if(n[1] != obj.targetTile[1]) continue;                                // same-Y adjacency, matches atDestination
    consider(n);
  }
  return goalTile;
}

bool canMoveTo(T)(T wd, float[3] pos) {
  foreach (dx; -1..2) foreach (dy; -1..2) foreach (dz; -1..2) {
    float[3] p = [pos[0] + dx * wd.tileSize * 0.5f, pos[1] + dy * wd.tileHeight * 0.5f, pos[2] + dz * wd.tileSize * 0.5f];
    if (!wd.isPassable(wd.worldToTile(p))) return(false);
  }
  return(true);
}
