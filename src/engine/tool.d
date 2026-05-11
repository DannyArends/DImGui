/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import camera : castRay;
import chunk : getBestTile;
import color : colorIndex;
import ghost : syncBuildGhosts;
import inventory : placeTile, computeDragPreview;
import jobs : tryAssign, jobQueue, miningJob, interactFeatureJob;
import matrix : scale, translate;
import mouse : getHits;
import geometry : setColor;
import tile : tileToWorld, getTileAt;
import vegetation : getBestVegetation;

enum ToolMode : ubyte { Select, Mine, Build, Stockpile }

struct PaintState {
  bool     active = false;
  int[3]   start = [int.min, 0, int.min];
  int[3][] preview;
}

/** Primary press: left click / single tap */
void handlePrimaryPress(ref App app, float sx, float sy) {
  auto ray = app.camera.castRay(sx, sy);
  int[3] wc;

  final switch(app.world.activeTool) {
    case ToolMode.Select:
      auto hits = app.getHits(ray, app.showRays);
      if(hits.length > 0) {
        Job job;
        if(app.getBestTile(ray, wc)) job = miningJob(wc);
        foreach(ref ft; features) {
          bool matchFeature(string g) { return ft.parts.any!(p => g == ft.name ~ ":" ~ p.mesh); }
          if(app.getBestVegetation!(Feature, matchFeature)(ray, hits, app.world.features.get(ft.name, null), wc)) {
            job = interactFeatureJob(wc); break;
          }
        }
        if(job.name !is null && !app.tryAssign(job)) jobQueue ~= job;
        foreach(ref hit; hits) {
          auto obj = app.objects[hit.idx[0]];
          if(cast(Chunk)obj is null) { obj.setColor(Colors.yellowgreen); obj.window = true; break; }
        }
      }
      break;
    case ToolMode.Build:
      if(app.world.inventory.ghost.tile != noTile && app.world.inventory.ghost.type != ResourceType.None) {
        app.world.inventory.isDragging = true;
        app.world.inventory.dragPreview = [app.world.inventory.ghost.tile];
        app.syncBuildGhosts();
      }
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      if(!app.getBestTile(ray, wc)) break;
      app.world.paint.active  = true;
      app.world.paint.start   = wc;
      app.world.paint.preview = [wc];
      app.syncBuildGhosts();
      break;
  }
}

/** Primary drag: left hold + move / single finger move */
void handlePrimaryDrag(ref App app, float sx, float sy) {
  auto ray = app.camera.castRay(sx, sy);
  int[3] wc;

  final switch(app.world.activeTool) {
    case ToolMode.Select:
      break;
    case ToolMode.Build:
      if(app.world.inventory.isDragging && app.world.inventory.ghost.tile != noTile &&
         app.world.inventory.dragPreview.length > 0) {
        app.computeDragPreview(app.world.inventory.dragPreview[0], app.world.inventory.ghost.tile);
        app.syncBuildGhosts();
      }
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      if(!app.world.paint.active) break;
      if(!app.getBestTile(ray, wc)) break;
      app.updatePaintPreview(wc);
      break;
  }
}

/** Primary release: left up / finger up */
void handlePrimaryRelease(ref App app, float sx, float sy) {
  auto ray = app.camera.castRay(sx, sy);

  final switch(app.world.activeTool) {
    case ToolMode.Select:
      break;
    case ToolMode.Build:
      if(app.world.inventory.isDragging) {
        foreach(tile; app.world.inventory.dragPreview) app.placeTile(tile);
        app.world.inventory.isDragging = false;
        app.world.inventory.dragPreview = [];
        app.syncBuildGhosts();
      } else if(app.world.inventory.ghost.tile != noTile) {
        app.placeTile(app.world.inventory.ghost.tile);
      }
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      if(app.world.paint.active) app.commitPaint();
      break;
  }
}

/** Secondary press: right click */
void handleSecondaryPress(ref App app, float sx, float sy) {
  final switch(app.world.activeTool) {
    case ToolMode.Select:
      break;
    case ToolMode.Build:
      app.world.inventory.ghost.type = ResourceType.None;
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      app.world.paint = PaintState.init;
      app.syncBuildGhosts();
      break;
  }
}

void updateHoverHighlight(ref App app, float sx, float sy) {
  if(app.world.activeTool != ToolMode.Mine && app.world.activeTool != ToolMode.Stockpile) return;
  auto ray = app.camera.castRay(sx, sy);
  int[3] wc;
  if(!app.getBestTile(ray, wc)) { app.world.paint.preview = []; app.syncBuildGhosts(); return; }
  app.world.paint.preview = [wc];
  app.syncBuildGhosts();
}

/** Update rectangular paint preview from anchor to current tile */
void updatePaintPreview(ref App app, int[3] current) {
  if(app.world.paint.start[0] == int.min) return;
  auto from = app.world.paint.start;
  app.world.paint.preview = [];
  int x0 = min(from[0], current[0]), x1 = max(from[0], current[0]);
  int z0 = min(from[2], current[2]), z1 = max(from[2], current[2]);
  for(int x = x0; x <= x1; x++)
    for(int z = z0; z <= z1; z++)
      app.world.paint.preview ~= [x, from[1], z];
  app.syncBuildGhosts();
}

/** Commit the current paint preview */
void commitPaint(ref App app) {
  if(app.world.paint.preview.length == 0) return;
  final switch(app.world.activeTool) {
    case ToolMode.Select: break;
    case ToolMode.Build:  break;
    case ToolMode.Mine:
      foreach(tile; app.world.paint.preview) {
        if(app.world.getTileAt(tile) == ResourceType.None) continue;
        auto job = miningJob(tile);
        if(!app.tryAssign(job)) jobQueue ~= job;
      }
      break;
    case ToolMode.Stockpile:
      break; // TODO: designate stockpile zone
  }
  app.world.paint = PaintState.init;
  app.syncBuildGhosts();
}
