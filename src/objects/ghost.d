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
  // Find which neighbour face was hit using ray direction
  float[3] dir = ray[1];
  int[3][6] neighbours = app.world.tileNeighbours(wc);
  float[3][6] normals = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
  float bestDot = float.max;
  int bestFace = 0;
  foreach(f; 0..6) {
    float dot = dir[0]*normals[f][0] + dir[1]*normals[f][1] + dir[2]*normals[f][2];
    if(dot < bestDot) { bestDot = dot; bestFace = f; }
  }
  auto target = neighbours[bestFace];
  auto coord = app.world.chunkCoord(target);
  if(coord in app.world.chunks) {
    auto idx = app.world.tileIndex(app.world.localCoord(target));
    if(app.world.chunks[coord].tileTypes[idx] == TileType.None) return target;
  } else { if(app.world.getTile(target) == TileType.None) return target; }
  return [int.min, 0, 0];
}

void updateGhostTile(ref App app) {
  if(app.inventory.selectedTile != TileType.None) {
    auto ray = app.camera.castRay(app.gui.io.MousePos.x, app.gui.io.MousePos.y);
    auto ghost = app.getGhostTile(ray);
    app.inventory.ghostTile = ghost;
    if(ghost[0] != int.min) {
      auto wp = app.world.worldPos(ghost);
      app.inventory.ghostCube.position([wp[0], wp[1] + app.world.yOffset, wp[2]]);
      auto name = tileData[app.inventory.selectedTile].name;
      auto uvT = app.tileAtlas.tileUVTransform(name);
      foreach(ref inst; app.inventory.ghostCube.instances) inst.uvT = uvT;
      app.inventory.ghostCube.buffers[INSTANCE] = false;
      app.inventory.ghostCube.isVisible = true;
    } else {
      app.inventory.ghostCube.isVisible = false;
    }
  } else {
    app.inventory.ghostTile = [int.min, 0, 0];
    app.inventory.ghostCube.isVisible = false;
  }
}


