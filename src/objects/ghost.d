/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import chunk : getBestTile;
import geometry : position;
import camera : castRay;
import tileatlas : tileData, tileUVTransform;
import intersection : intersects;

int[3] getGhostTile(ref App app, float[3][2] ray) {
  int[3] wc;
  if(!app.getBestTile(ray, wc)) return [int.min, 0, 0];
  float[3] dir = ray[1];
  int[3][6] neighbours = app.world.tileNeighbours(wc);
  float[3][6] normals = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];

  // Sort faces by dot product, try each in order until we find an empty neighbour
  int[6] order = [0,1,2,3,4,5];
  float[6] dots;
  foreach(f; 0..6) dots[f] = dir[0]*normals[f][0] + dir[1]*normals[f][1] + dir[2]*normals[f][2];
  order[].sort!((a,b) => dots[a] < dots[b]);

  foreach(f; order) {
    if(dots[order[0]] < 0 && dots[f] > -0.1f) break; // skip near-perpendicular faces
    auto target = neighbours[f];
    auto coord = app.world.chunkCoord(target);
    if(coord in app.world.chunks) {
      auto idx = app.world.tileIndex(app.world.localCoord(target));
      if(app.world.chunks[coord].tileTypes[idx] == TileType.None) return target;
    } else {
      if(app.world.getTile(target) == TileType.None) return target;
    }
  }
  return [int.min, 0, 0];
}

void updateGhostTile(ref App app) {
  if(app.inventory.selectedTile == TileType.None) {
    app.inventory.ghostTile = [int.min, 0, 0];
    app.inventory.ghostCube.isVisible = false;
    return;
  }
  auto ray = app.camera.castRay(app.gui.io.MousePos.x, app.gui.io.MousePos.y);
  auto ghost = app.getGhostTile(ray);
  app.inventory.ghostTile = ghost;
  app.inventory.ghostCube.isVisible = ghost[0] != int.min;
  if(ghost[0] != int.min) {
    auto wp = app.world.worldPos(ghost);
    app.inventory.ghostCube.position([wp[0], wp[1] + app.world.yOffset, wp[2]]);
    auto uvT = app.tileAtlas.tileUVTransform(tileData[app.inventory.selectedTile].name);
    foreach(ref inst; app.inventory.ghostCube.instances) inst.uvT = uvT;
    app.inventory.ghostCube.buffers[INSTANCE] = false;
  }
}

