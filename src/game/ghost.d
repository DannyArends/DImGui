/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import chunk : getBestTile;
import game : GameApp;
import vector : dot;
import tool : tools, buildHighlight;
import tile : tileIdx, tileToWorld, tileAbove;
import jobs : activeTiles;

int[3] getGhostTile(const GameApp app, float[3][2] ray, Intersection[] hits) {
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

void addTiles(ref World world, const(int[3])[] tiles, ToolMode mode) {
  if(tools[mode].matrix is null) return;               // tools with no ghost (e.g. Select/Query)
  foreach(tile; tiles) {
    auto inst = DrawInstance([0, 0], tools[mode].color, Matrix.init);
    inst.matrix = tools[mode].matrix(world.tileToWorld(tile), world.tileSize, world.tileHeight);
    world.inventory.instances ~= inst;
  }
}

/** Update Orchestrator */
void syncBuildGhosts(ref GameApp app) {
  if(app.world.inventory is null) return;
  app.world.inventory.instances = [];
  app.world.data.tilePenalties = null;

  auto buildTiles = app.world.activeTiles("Building");
  auto mineTiles = app.world.activeTiles("Mining");

  app.world.addTiles(buildTiles, ToolMode.Build);
  foreach(tile; buildTiles) app.world.data.tilePenalties[tile] = 40.0f;
  app.world.addTiles(mineTiles, ToolMode.Mine);
  foreach(ref sp; app.world.stockpiles){ foreach(t; sp.tiles) {
    app.world.addTiles([t], ToolMode.Stockpile);
    app.world.data.tilePenalties[t.tileAbove] = 100.0f;
  } }
  app.world.addTiles(app.world.inventory.paint.preview, app.world.inventory.activeTool);

  app.world.inventory.isVisible = (app.world.inventory.instances.length > 0);
  app.world.inventory.instances.invalidate();
  if(app.world.inventory.box !is null) app.world.inventory.box.dirty = true;
}

