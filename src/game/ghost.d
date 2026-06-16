/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : getBestTile;
import game : GameApp;
import vector : dot;
import tool : tools, buildHighlight;
import tile : tileIdx, tileToWorld;
import jobs : activeTiles;

int[3] getGhostTile(ref GameApp app, float[3][2] ray, Intersection[] hits) {
  int[3] wc;
  if(!app.getBestTile(ray, hits, wc)) { return(noTile); }

  int[3][6] neighbours = app.world.tileNeighbours(wc);
  float ts = app.world.tileSize, th = app.world.tileHeight;
  float[3][6] normals = [
    [th/ts, 0.0f, 0.0f],  [-th/ts, 0.0f, 0.0f],     /// X faces: area = ts*th, scaled down
    [0.0f,  1.0f, 0.0f],  [0.0f,  -1.0f, 0.0f],     /// Y faces: area = ts*ts, full weight
    [0.0f,  0.0f, th/ts], [0.0f,   0.0f, -th/ts]    /// Z faces: area = ts*th, scaled down
  ];

  /// Sort faces by dot product, try each in order until we find an empty neighbour
  uint[6] order = [0, 1, 2, 3, 4, 5];
  float[6] dots;
  foreach(f; order) dots[f] = ray[1].dot(normals[f]);
  foreach(f; order[].sort!((a,b) => dots[a] < dots[b])) {
    if(neighbours[f][1] < 0 || neighbours[f][1] >= app.world.chunkHeight) continue;
    auto coord = app.world.chunkCoord(neighbours[f]);
    auto tidx = app.world.tileIdx(neighbours[f]);
    if(app.world.chunks[coord].tileTypes[tidx] == ResourceType.None) return(neighbours[f]);
  }
  return(noTile);
}

void updateGhostTile(ref GameApp app, float[3][2] ray, Intersection[] hits) {
  if(app.world.inventory.activeTool != ToolMode.Build) return;
  int[3] newTile = app.getGhostTile(ray, hits);
  if(newTile == app.world.inventory.tile) return;
  app.world.inventory.tile = newTile;
  app.syncBuildGhosts();
}

void addTiles(ref GameApp app, int[3][] tiles, ToolMode mode) {
  auto h = tools[mode];
  float ts = app.world.tileSize, th = app.world.tileHeight;
  foreach(tile; tiles) {
    auto inst = DrawInstance([0, 0], h.color, Matrix.init);
    inst.matrix = h.matrix(app.world.tileToWorld(tile), ts, th);
    app.world.inventory.instances ~= inst;
  }
}

/** Cursor ghost (single tile with texture) */
void syncCursorGhost(ref GameApp app) {
  if(app.world.inventory.activeTool != ToolMode.Build) return;
  if(app.world.inventory.tile == noTile) return;
  auto wp = app.world.tileToWorld(app.world.inventory.tile);
  app.world.inventory.instances ~= DrawInstance(app.world.inventory.cachedMatIdx, buildHighlight(wp, app.world.tileSize, app.world.tileHeight));
}

/** Update Orchestrator */
void syncBuildGhosts(ref GameApp app) {
  if(app.world.inventory is null) return;
  app.world.inventory.instances = [];

  auto buildTiles = app.activeTiles("Building");
  auto mineTiles = app.activeTiles("Mining");

  app.addTiles(buildTiles, ToolMode.Build);
  foreach(tile; buildTiles) app.world.data.tilePenalties[tile] = 40.0f;
  app.addTiles(mineTiles, ToolMode.Mine);
  app.addTiles(app.world.inventory.paint.preview, app.world.inventory.activeTool);
  app.syncCursorGhost();

  app.world.inventory.isVisible = (app.world.inventory.instances.length > 0);
  app.world.inventory.instances.buffered = false;
}

