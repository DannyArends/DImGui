/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import lattice : tileToWorld, worldToTile, tileAbove, tileNeighbours, tileBelow;
import matrix : translate;
import search : performSearch, atGoal, stepThroughPath;
import tile : getSuccessors, isStandable, isPassable, getTileAt;
import vector : manhattan2D;

struct PathRequest {
  uint uid;
  int[3] fromTile;
  int[3] goalTile;
}

struct PathResult {
  uint uid;
  float[3][] path;
  bool success;
  bool partial;
}

/** Outcome of a repath attempt. */
enum RepathResult { Unreachable, AtTarget, Pathing }

struct PathMarker {
  PathMarkers markers;
  PathRequest[] pending;
  void delegate(PathResult)[uint] onResult;
}

/** Log a failed path search with closest-approach diagnostics */
void logPathFail(S)(ref S result, PathRequest req) {
  float minH = float.max;
  foreach(idx; result.closedset.byValue) if(result.pool[idx].h < minH) minH = result.pool[idx].h;
  SDL_Log(cstr("PATHFAIL state=%s from=%s goal=%s steps=%d open=%d closed=%d minH=%.2f stand=%d",
          result.state, req.fromTile, req.goalTile, result.steps, result.openlist.length, result.closedset.length, minH, result.map.isStandable(req.goalTile)));
}

/** Send a request to a free worker; returns false if none are idle. */
private bool trySendPath(ref GameApp app, PathRequest req) {
  foreach(tid; app.concurrency.workers.keys) {
    if(!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, req);
      return true;
    }
  }
  return false;
}

/** Pathfinding on a worker thread */
PathResult pathfindWorker(immutable(WorldData) wd, PathRequest req) {
  float[3] start = wd.tileToWorld(req.fromTile);
  float[3] goal  = wd.tileToWorld(req.goalTile);
  auto result = performSearch!(WorldData, PathNode, getSuccessors)(start, goal, cast(WorldData)wd, false);
  if(result.state != SearchState.SUCCEEDED && result.state != SearchState.PARTIAL) {
    result.logPathFail(req);
    return PathResult(req.uid, [], false);
  }
  float[3][] path;
  while(result.pathptr != size_t.max && !result.atGoal()) path ~= result.stepThroughPath(false);
  path ~= result.pool[result.goal].position;
  return PathResult(req.uid, path, true, (result.state == SearchState.PARTIAL));
}

/** Pathfind object T to goalTile; onDone(result) is invoked on the main thread when the search completes.
 * Requires T to have: uid, tile. Caller owns entity state. */
void pathfindTo(T)(ref GameApp app, ref T obj, int[3] goalTile, void delegate(PathResult) onDone) {
  app.world.paths.pending = app.world.paths.pending.filter!(r => r.uid != obj.uid).array;
  app.world.paths.onResult[obj.uid] = onDone;
  auto req = PathRequest(obj.uid, obj.tile, goalTile);
  if(!app.trySendPath(req)) app.world.paths.pending ~= req;
  obj.state = EntityState.WaitingForPath;
}

/** Route a completed path back to whoever requested it. */
void dispatchPathResult(ref GameApp app, PathResult r) {
  if(auto cb = r.uid in app.world.paths.onResult) {
    app.world.paths.onResult.remove(r.uid);
    (*cb)(r);
  }
}

/** Dispatch queued path requests to any idle workers. */
void dispatchPendingPaths(ref GameApp app) {
  if(app.concurrency.paths.length > 0) return;
  while(app.world.paths.pending.length > 0 && app.trySendPath(app.world.paths.pending[0])) {
    app.world.paths.pending = app.world.paths.pending[1..$];
  }
}

/** Follow the next step in object T's path. Requires T to have: tile, path, visualPos, moveFrom, moveTo, moveT */
void followPath(T)(ref GameApp app, ref T obj) {
  if(obj.path.length == 0) return;
  auto next = obj.path[0];
  obj.path = obj.path[1..$];
  obj.moveFrom = obj.visualPos;
  obj.moveTo = [next[0], next[1], next[2]];
  obj.moveT = 0.0f;
  obj.tile = app.world.worldToTile(next);
  app.camera.isDirty = true;
}

/** Advance one entity's interpolated step; returns true while still moving. Requires tile/visualPos/moveFrom/moveTo/moveT/path. */
bool stepMove(T)(ref GameApp app, ref T obj, float dt, float speed, float hop) {
  if(obj.moveT >= 1.0f) return false;
  float cost = max(1.0f, app.world.getTileAt(obj.tile.tileBelow).cost);
  obj.moveT = min(1.0f, obj.moveT + dt * speed / cost);
  float arc = hop * obj.moveT * (1.0f - obj.moveT);
  obj.visualPos = [
    obj.moveFrom[0] + obj.moveT * (obj.moveTo[0] - obj.moveFrom[0]),
    obj.moveFrom[1] + obj.moveT * (obj.moveTo[1] - obj.moveFrom[1]) + arc,
    obj.moveFrom[2] + obj.moveT * (obj.moveTo[2] - obj.moveFrom[2])
  ];
  if(obj.moveT < 1.0f) return false;
  if(obj.path.length > 0) { app.followPath(obj); return false; }
  return true;
}

/** Re-path object T toward targetTile via onDone. Requires T to have: tile, targetTile, path. */
RepathResult repathTo(T)(ref GameApp app, ref T obj, int[3] targetTile, Reach reach, void delegate(PathResult) onDone) {
  obj.targetTile = targetTile;
  auto goal = app.world.findGoalTile(targetTile, obj.tile, reach);
  if(goal == noTile) return RepathResult.Unreachable;
  if(goal == obj.tile) { obj.path = []; return RepathResult.AtTarget; }
  app.pathfindTo(obj, goal, onDone);
  return RepathResult.Pathing;
}

/** Closest standable tile satisfying `reach` around targetTile, or noTile. */
int[3] findGoalTile(const World world, const int[3] targetTile, const int[3] from, Reach reach = Reach.Adjacent) {
  if(reach == Reach.OnTile) return world.isStandable(targetTile) ? targetTile : noTile;

  int[3] best = noTile;
  float bestScore = float.max;
  void consider(int[3] n) {
    if(!world.isStandable(n)) return;
    float score = manhattan2D(n, from) + world.data.tilePenalties.get(n, 0.0f);
    if(score < bestScore) { bestScore = score; best = n; }
  }

  if(reach == Reach.AdjacentOrAbove) consider(targetTile.tileAbove);   // standing on top is valid
  if(reach == Reach.AdjacentOrOnTile) consider(targetTile);            // standing on the tile itself is valid
  auto nb = tileNeighbours(targetTile);
  foreach(i; [0, 1, 4, 5]) { if(nb[i][1] == targetTile[1]) consider(nb[i]); }   // ±x/±z, same-Y = manhattan2D==1
  return best;
}

/** Helper to figure out if a dwarf can move to */
bool canMoveTo(T)(T wd, float[3] pos) {
  foreach (dx; -1..2) foreach (dy; -1..2) foreach (dz; -1..2) {
    float[3] p = [pos[0] + dx * wd.tileSize * 0.5f, pos[1] + dy * wd.tileHeight * 0.5f, pos[2] + dz * wd.tileSize * 0.5f];
    if (!wd.isPassable(wd.worldToTile(p))) return(false);
  }
  return(true);
}
