/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import lattice : tileToWorld, worldToTile, tileAbove, tileNeighbours;
import matrix : translate;
import search : performSearch, atGoal, stepThroughPath;
import tile : getSuccessors, isStandable, isPassable;
import vector : manhattan2D;

struct PathRequest {
  uint dwarfUID;
  int[3] fromTile;
  int[3] goalTile;
}

struct PathResult {
  uint dwarfUID;
  float[3][] path;
  bool success;
  bool partial;
}

struct PathMarker {
  PathMarkers markers;
  PathRequest[] pending;
}

/** Log a failed path search with closest-approach diagnostics */
void logPathFail(S)(ref S result, PathRequest req) {
  float minH = float.max;
  foreach(idx; result.closedset.byValue) if(result.pool[idx].h < minH) minH = result.pool[idx].h;
  SDL_Log(cstr("PATHFAIL state=%s from=%s goal=%s steps=%d open=%d closed=%d minH=%.2f stand=%d",
          result.state, req.fromTile, req.goalTile, result.steps, result.openlist.length, result.closedset.length, minH, result.map.isStandable(req.goalTile)));
}

/** Pathfinding on a worker thread */
PathResult pathfindWorker(immutable(WorldData) wd, PathRequest req) {
  float[3] start = wd.tileToWorld(req.fromTile);
  float[3] goal  = wd.tileToWorld(req.goalTile);
  auto result = performSearch!(WorldData, PathNode, getSuccessors)(start, goal, cast(WorldData)wd, false);
  if(result.state != SearchState.SUCCEEDED && result.state != SearchState.PARTIAL) {
    result.logPathFail(req);
    return PathResult(req.dwarfUID, [], false);
  }
  float[3][] path;
  while(result.pathptr != size_t.max && !result.atGoal()) path ~= result.stepThroughPath(false);
  path ~= result.pool[result.goal].position;
  return PathResult(req.dwarfUID, path, true, (result.state == SearchState.PARTIAL));
}

/** Rebuild path marker instances from all dwarf paths */
void syncPathMarkers(ref World world, bool showPaths = false) {
  if(world.paths.markers is null || world.dwarves is null) return;
  world.paths.markers.instances.reset();
  if(showPaths) {
    foreach(ref d; world.dwarves) {
      foreach(l; d.path) { world.paths.markers.instances ~= DrawInstance(translate([l[0], l[1] - 0.4f, l[2]]), -1, d.color); }
    }
  }
  world.paths.markers.syncInstances();
}

/** Pathfind object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, path */
void pathfindTo(T)(ref GameApp app, ref T obj, int[3] goalTile) {
  app.world.paths.pending = app.world.paths.pending.filter!(r => r.dwarfUID != obj.uid).array;  // Remove any existing pending request for this dwarf
  auto req = PathRequest(obj.uid, obj.tile, goalTile);
  foreach(tid; app.concurrency.workers.keys) {
    if(!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, req);
      obj.state = DwarfState.WaitingForPath;
      return;
    }
  }
  app.world.paths.pending ~= req;
  obj.state = DwarfState.WaitingForPath;
}

/** Dispatch pending path finding jobs */
void dispatchPendingPaths(ref GameApp app) {
  if(app.concurrency.paths.length > 0) return;
  foreach(tid; app.concurrency.workers.keys) {
    if(app.world.paths.pending.length == 0) break;
    if(!app.concurrency.workers[tid]) {
      app.concurrency.workers[tid] = true;
      tid.send(cast(immutable(WorldData))app.world.data, app.world.paths.pending[0]);
      app.world.paths.pending = app.world.paths.pending[1..$];
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
  auto goal = app.world.findGoalTile(targetTile, obj.tile, reach);
  if(goal == noTile) return false;
  if(goal == obj.tile) { obj.path = []; obj.state = DwarfState.Working; return true; }
  app.pathfindTo(obj, goal);
  return true;
}

/** Find the closest standable neighbour (air tile with solid below) to the object.
 * Requires T to have: tile, targetTile */
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
