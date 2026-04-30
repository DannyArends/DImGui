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

void applyPathResult(ref App app, PathResult result) {
  if(app.world.dwarves is null) return;
  foreach(ref d; app.world.dwarves) {
    if(d.uid != result.dwarfUID) continue;
    if(!result.success) { if(d.jobStack.length > 0) d.jobStack[0].onFail(app, d); return; }
    d.path = result.path;
    d.moveFrom = d.visualPos;
    d.moveTo = d.visualPos;
    d.moveT = 1.0f;
    return;
  }
}

/** Pathfind object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, path */
bool pathfindTo(T)(ref App app, ref T obj, int[3] goalTile) {
  auto req = PathRequest(obj.uid, obj.tile, goalTile);
  foreach(tid; app.concurrency.workers.keys) {
    if(!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, req);
      return true;
    }
  }
  app.world.pendingPaths ~= req;
  return true;
}

/** Check if object T is adjacent to targetTile.
 * Requires T to have: tile */
bool atDestination(T)(ref App app, ref T obj, int[3] targetTile) {
  auto dx = abs(obj.tile[0] - targetTile[0]);
  auto dz = abs(obj.tile[2] - targetTile[2]);
  return dx + dz == 1 && obj.tile[1] == targetTile[1];
}

/** Attempt to re-path object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, targetTile, path, visualPos, moveFrom, moveTo, moveT */
bool repathTo(T)(ref App app, ref T obj, int[3] targetTile) {
  obj.targetTile = targetTile;
  auto goalTile = app.findGoalTile(obj);
  if(goalTile[0] == int.min) return false;
  if(!app.pathfindTo(obj, goalTile)) return false;
  obj.moveFrom = obj.visualPos;
  obj.moveTo = obj.visualPos;
  obj.moveT = 1.0f;
  return true;
}

/** Find the closest standable neighbour (air tile with solid below) to the object.
 * Requires T to have: tile, targetTile */
int[3] findGoalTile(T)(ref App app, ref T obj) {
  int[3] goalTile = [int.min, 0, 0];
  float bestDist = float.max;
  foreach(n; app.world.tileNeighbours(obj.targetTile)[0..2] ~ app.world.tileNeighbours(obj.targetTile)[4..6]) {
    if(!app.world.isStandable(n)) continue;
    float dist = abs(n[0]-obj.tile[0]) + abs(n[2]-obj.tile[2]);
    if(dist < bestDist) { bestDist = dist; goalTile = n; }
  }
  return goalTile;
}

/** Follow the next step in object T's path.
 * Requires T to have: tile, path, visualPos, moveFrom, moveTo, moveT */
void followPath(T)(ref App app, ref T obj) {
  if(obj.path.length == 0) return;
  auto next = obj.path[0];
  obj.path = obj.path[1..$];
  obj.moveFrom = obj.visualPos;
  obj.moveTo = [next[0], next[1] - 0.5f, next[2]];
  obj.moveT = 0.0f;
  obj.tile = app.world.worldToTile(next);
  app.camera.isDirty = true;
}

