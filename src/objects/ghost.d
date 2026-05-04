/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : colorIndex;
import chunk : getBestTile;
import resources : resourceData;
import textures : idx;
import vector : dot;
import matrix : position, scale, translate;
import world : noTile;
import jobs : jobQueue;

class GhostCube : Cube {
  ResourceType type = ResourceType.None;
  int[3] tile = noTile;

  this(float[2] dim, bool instanced = false) {
    super(color: [1.0f, 1.0f, 1.0f, 1.0f]);
    isSelectable = false;
    isVisible = false;
    castShadow = false;
    scale([dim[0], dim[1], dim[0]]);
    geometry = (){ return(typeof(this).stringof); };
    if(instanced) initInstanced(() => "BuildingGhosts");
  }
}

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
  if(app.world.inventory.ghost.type == ResourceType.None) {
    app.world.inventory.ghost.tile = noTile;
    app.world.inventory.ghost.isVisible = false;
    return;
  }else{ app.world.inventory.ghost.isVisible = true; }
  app.world.inventory.ghost.tile = app.getGhostTile(ray);
  if(app.world.inventory.ghost.isVisible) {
    app.world.inventory.ghost.position(app.world.tileToWorld(app.world.inventory.ghost.tile));
    foreach (k, ref m; app.world.inventory.ghost.meshes) {
      m.tid = app.textures.idx(resourceData(app.world.inventory.ghost.type).name ~ "_base");
    }
    app.buffers["MeshMatrices"].dirty[] = true;
  }
}

void syncBuildGhosts(ref App app) {
  if(app.world.buildingGhosts is null) return;
  app.world.buildingGhosts.instances = [];
  uint committed = colorIndex(Colors.dodgerblue);
  uint preview = colorIndex(Colors.darkslateblue);

  void addInstance(int[3] tile, uint color) {
    auto inst = DrawInstance([0, 0, color, 0]);
    inst.matrix = inst.matrix.scale([app.world.tileSize, app.world.tileHeight, app.world.tileSize]);
    inst.matrix = inst.matrix.translate(app.world.tileToWorld(tile));
    app.world.buildingGhosts.instances ~= inst;
  }

  foreach(key; app.world.data.tilePenalties.keys) { if(app.world.data.tilePenalties[key] >= 20.0f) app.world.data.tilePenalties.remove(key); }
  foreach(ref j; jobQueue) { if(j.name == "Building") { addInstance(j.targetTile, committed); app.world.data.tilePenalties[j.targetTile] = 40.0f; } }
  if(app.world.dwarves !is null) {
    foreach(ref d; app.world.dwarves) { foreach(ref j; d.jobStack) { 
      if(j.name == "Building") { addInstance(j.targetTile, committed); app.world.data.tilePenalties[j.targetTile] = 40.0f; }
    } }
  }
  foreach(tile; app.world.inventory.dragPreview) addInstance(tile, preview);
  app.world.buildingGhosts.isVisible = (app.world.buildingGhosts.instances.length > 0);
  app.world.buildingGhosts.markDirty();
}
