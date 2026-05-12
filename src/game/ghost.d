/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : colorIndex;
import chunk : getBestTile;
import textures : idx;
import vector : dot;
import matrix : translateScale;
import tile : tileIdx, tileToWorld;

int[3] getGhostTile(ref App app, float[3][2] ray) {
  int[3] wc;
  if(!app.getBestTile(ray, wc)) { return(noTile); }

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

void updateGhostTile(ref App app, float[3][2] ray) {
  if(app.world.inventory.activeTool != ToolMode.Build) return;
  app.world.inventory.tile = app.world.inventory.type == ResourceType.None ? noTile : app.getGhostTile(ray);
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

ubyte highlightStyle(ToolMode mode) {
  final switch(mode) {
    case ToolMode.Select: return 0;
    case ToolMode.Build: return 0;
    case ToolMode.Mine: return 1;
    case ToolMode.Stockpile: return 2;
  }
}

void addInstance(ref App app, int[3] tile, uint color, ubyte style) {
  auto wp = app.world.tileToWorld(tile);
  float ts = app.world.tileSize, th = app.world.tileHeight;
  auto inst = DrawInstance([0, 0, color, -1]);
  final switch(style) {
    case 0: inst.matrix = buildHighlight(wp, ts, th); break;
    case 1: inst.matrix = mineHighlight(wp, ts, th); break;
    case 2: inst.matrix = stockpileHighlight(wp, ts, th); break;
  }
  app.world.inventory.instances ~= inst;
}

/** Committed designations + tile penalties */
void syncDesignations(ref App app) {
  foreach(tile; app.world.inventory.buildDesignations) {
    app.addInstance(tile, colorIndex(Colors.dodgerblue), 0);
    app.world.data.tilePenalties[tile] = 40.0f;
  }
  foreach(tile; app.world.inventory.mineDesignations){ app.addInstance(tile, colorIndex(Colors.orangered), 1); }
}

/** Paint preview (drag highlight) */
void syncPaintPreview(ref App app) {
  uint paintColor;
  final switch(app.world.inventory.activeTool) {
    case ToolMode.Select:    paintColor = colorIndex(Colors.white);      break;
    case ToolMode.Mine:      paintColor = colorIndex(Colors.orangered);  break;
    case ToolMode.Build:     paintColor = colorIndex(Colors.dodgerblue); break;
    case ToolMode.Stockpile: paintColor = colorIndex(Colors.gold);       break;
  }
  foreach(tile; app.world.inventory.paint.preview) { app.addInstance(tile, paintColor, highlightStyle(app.world.inventory.activeTool)); }
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

/** Update Orchestrator */
void syncBuildGhosts(ref App app) {
  if(app.world.inventory is null) return;
  app.world.inventory.instances = [];
  app.syncDesignations();
  app.syncPaintPreview();
  app.syncCursorGhost();
  app.world.inventory.isVisible = (app.world.inventory.instances.length > 0);
  app.world.inventory.markDirty();
}

