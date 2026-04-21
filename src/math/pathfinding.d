/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import search : performSearch, atGoal, stepThroughPath;
import world : tileToWorld, isStandable, isTileOccupied;

/** Pathfind object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, path */
bool pathfindTo(T)(ref App app, T obj, int[3] goalTile) {
  float[3] start = app.tileToWorld(obj.tile);
  float[3] goal  = app.tileToWorld(goalTile);
  if(app.verbose) SDL_Log(toStringz(format("pathfindTo: %s -> %s", start, goal)));
  auto result = performSearch!(World, PathNode)(start, goal, app.world, app.verbose > 0);
  if(app.verbose) SDL_Log(toStringz(format("Search: %s steps: %d", result.state, result.steps)));
  if(result.state == SearchState.FAILED || result.state == SearchState.INVALID) return false;
  obj.path = [];
  while(result.pathptr != size_t.max && !result.atGoal()) obj.path ~= result.stepThroughPath(app.trace);
  obj.path ~= result.pool[result.goal].position;
  return true;
}

/** Check if object T is adjacent to targetTile.
 * Requires T to have: tile */
bool atDestination(T)(ref App app, T obj, int[3] targetTile) {
  auto dx = abs(obj.tile[0] - targetTile[0]);
  auto dz = abs(obj.tile[2] - targetTile[2]);
  return dx + dz == 1 && obj.tile[1] == targetTile[1];
}

/** Attempt to re-path object T to goalTile, returns false if unreachable.
 * Requires T to have: tile, targetTile, path, visualPos, moveFrom, moveTo, moveT */
bool repathTo(T)(ref App app, T obj, int[3] targetTile) {
  obj.targetTile = targetTile;
  auto goalTile = app.findGoalTile(obj);
  if(goalTile[0] == int.min) return false;
  return app.pathfindTo(obj, goalTile);
}

/** Find the closest standable neighbour (air tile with solid below) to the object.
 * Requires T to have: tile, targetTile */
int[3] findGoalTile(T)(ref App app, T obj) {
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
void followPath(T)(ref App app, T obj) {
  if(obj.path.length == 0) return;
  auto next = obj.path[0];
  obj.path = obj.path[1..$];
  obj.moveFrom = obj.visualPos;
  obj.moveTo = [next[0], next[1] - 0.5f, next[2]];
  obj.moveT = 0.0f;
  obj.tile = app.world.worldToTile(next);
}

