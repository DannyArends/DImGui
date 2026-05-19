/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import chunk : getBestTile;
import textures : idx;
import vector : dot;
import matrix : translateScale;
import tile : tileIdx, tileToWorld;

int[3] getGhostTile(ref App app, float[3][2] ray, Intersection[] hits) {
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

void updateGhostTile(ref App app, float[3][2] ray, Intersection[] hits) {
  if(app.world.inventory.activeTool != ToolMode.Build) return;
  int[3] newTile = app.world.inventory.type == ResourceType.None ? noTile : app.getGhostTile(ray, hits);
  if(newTile == app.world.inventory.tile) return;
  app.world.inventory.tile = newTile;
  app.syncBuildGhosts();
}

Matrix mineHighlight(float[3] wp, float ts, float th) {
  return translateScale([wp[0], wp[1], wp[2]], [ts * 1.05f, th * 1.05f, ts * 1.05f]);
}

Matrix buildHighlight(float[3] wp, float ts, float th) {
  return translateScale([wp[0], wp[1], wp[2]], [ts, th, ts]);
}

Matrix stockpileHighlight(float[3] wp, float ts, float th) {
  return translateScale([wp[0], wp[1] + 0.5f * th, wp[2]], [ts * 1.05f, th * 0.1f, ts * 1.05f]);
}
/** Per-tool highlight: color and matrix builder */
struct ToolHighlight {
  float[4]  color;
  Matrix function(float[3], float, float) matrix;
}

immutable ToolHighlight[ToolMode.max + 1] toolHighlight = [
  ToolMode.Select: { Colors.white, &buildHighlight },
  ToolMode.Mine: { Colors.orangered, &mineHighlight },
  ToolMode.Build: { Colors.dodgerblue, &buildHighlight },
  ToolMode.Stockpile: { Colors.gold, &stockpileHighlight },
];

void addTiles(ref App app, int[3][] tiles, ToolMode mode) {
  auto h = toolHighlight[mode];
  float ts = app.world.tileSize, th = app.world.tileHeight;
  foreach(tile; tiles) {
    auto inst = DrawInstance([0, 0], h.color, Matrix.init);
    inst.matrix = h.matrix(app.world.tileToWorld(tile), ts, th);
    app.world.inventory.instances ~= inst;
  }
}

/** Update Orchestrator */
void syncBuildGhosts(ref App app) {
  if(app.world.inventory is null) return;
  app.world.inventory.instances = [];

  app.addTiles(app.world.inventory.buildDesignations, ToolMode.Build);
  foreach(tile; app.world.inventory.buildDesignations) app.world.data.tilePenalties[tile] = 40.0f;
  app.addTiles(app.world.inventory.mineDesignations, ToolMode.Mine);
  app.addTiles(app.world.inventory.paint.preview, app.world.inventory.activeTool);
  app.syncCursorGhost();

  app.world.inventory.isVisible = (app.world.inventory.instances.length > 0);
  app.world.inventory.markDirty();
}

/** Cursor ghost (single tile with texture) */
void syncCursorGhost(ref App app) {
  if(app.world.inventory.activeTool != ToolMode.Build) return;
  if(app.world.inventory.tile == noTile) return;
  if(app.world.inventory.type == ResourceType.None) return;
  auto wp = app.world.tileToWorld(app.world.inventory.tile);
  float ts = app.world.tileSize, th = app.world.tileHeight;
  auto inst = DrawInstance([0, 0, 0, app.world.inventory.cachedTexIdx]);
  inst.matrix = buildHighlight(wp, ts, th);
  app.world.inventory.instances ~= inst;
}

