/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import camera : castRay;
import chunk : getBestTile;
import ghost : syncBuildGhosts;
import inventory : placeTile, computeDragPreview;
import jobs : tryAssign, jobQueue, miningJob, interactFeatureJob;
import hits : getHits;
import geometry : setColor;
import tile : tileToWorld, getTileAt;
import vegetation : getBestVegetation;

enum ToolMode : ubyte { Select, Mine, Build, Stockpile }

struct PaintState {
  bool active = false;
  int[3] start = [int.min, 0, int.min];
  int[3][] preview;
}

void selectObject(ref GameApp app, Intersection[] hits) {
  foreach(ref o; app.objects) o.window = false;
  foreach(ref hit; hits) {
    auto obj = app.objects[hit.idx[0]];
    if(cast(Chunk)obj is null) { obj.window = true; break; }
  }
}

/** Primary press: left click / single tap */
void handlePrimaryPress(ref GameApp app, float sx, float sy) {
  auto ray = app.camera.castRay(sx, sy);
  int[3] wc;

  final switch(app.world.inventory.activeTool) {
    case ToolMode.Select:
      auto hits = app.getHits(ray, app.showRays);
      if(hits.length > 0) {
        app.world.dwarves.selected = -1;
        foreach(ref hit; hits) {
          if(app.objects[hit.idx[0]] is app.world.dwarves) {
            if(hit.idx[1] < app.world.dwarves.dwarves.length) app.world.dwarves.selected = cast(int)hit.idx[1];
            break;
          }
        }
        Job job;
        if(app.getBestTile(ray, wc)) job = miningJob(wc);
        foreach(ref ft; features) {
          bool matchFeature(string g) { return ft.parts.any!(p => g == ft.name ~ ":" ~ p.mesh); }
          if(app.getBestVegetation!(Feature, matchFeature)(ray, hits, app.world.features.get(ft.name, null), wc)) {
            job = interactFeatureJob(wc); break;
          }
        }
        if(job.name !is null) app.tryAssign(job);
        app.selectObject(hits);
      }
      break;
    case ToolMode.Build:
      if(app.world.inventory.tile != noTile && app.world.inventory.type != ResourceType.None) {
        app.world.inventory.paint.active = true;
        app.world.inventory.paint.start = app.world.inventory.tile;
        app.world.inventory.paint.preview = [app.world.inventory.tile];
        app.syncBuildGhosts();
      }
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      if(!app.getBestTile(ray, wc)) break;
      app.world.inventory.paint.active  = true;
      app.world.inventory.paint.start = wc;
      app.world.inventory.paint.preview = [wc];
      app.syncBuildGhosts();
      break;
  }
}

/** Primary drag: left hold + move / single finger move */
void handlePrimaryDrag(ref GameApp app, float sx, float sy) {
  auto ray = app.camera.castRay(sx, sy);
  int[3] wc;

  final switch(app.world.inventory.activeTool) {
    case ToolMode.Select:
      break;
    case ToolMode.Build:
      if(!app.world.inventory.paint.active) break;
      if(app.world.inventory.tile == noTile) break;
      app.computeDragPreview(app.world.inventory.paint.start, app.world.inventory.tile);
      app.syncBuildGhosts();
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      if(!app.world.inventory.paint.active) break;
      if(!app.getBestTile(ray, wc)) break;
      app.updatePaintPreview(wc);
      break;
  }
}

/** Primary release: left up / finger up */
void handlePrimaryRelease(ref GameApp app, float sx, float sy) {
  final switch(app.world.inventory.activeTool) {
    case ToolMode.Select:
      break;
    case ToolMode.Build:
      if(app.world.inventory.paint.active) {
        foreach(tile; app.world.inventory.paint.preview) { app.placeTile(tile); }
        app.world.inventory.paint = PaintState.init;
        app.syncBuildGhosts();
      } else if(app.world.inventory.tile != noTile) { app.placeTile(app.world.inventory.tile); }
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      if(app.world.inventory.paint.active) app.commitPaint();
      break;
  }
}

/** Secondary press: right click */
void handleSecondaryPress(ref GameApp app, float sx, float sy) {
  final switch(app.world.inventory.activeTool) {
    case ToolMode.Select:
      break;
    case ToolMode.Build:
      app.world.inventory.type = ResourceType.None;
      break;
    case ToolMode.Mine:
    case ToolMode.Stockpile:
      app.world.inventory.paint = PaintState.init;
      app.syncBuildGhosts();
      break;
  }
}

void updateHoverHighlight(ref GameApp app, float sx, float sy) {
  if(app.world.inventory.activeTool != ToolMode.Mine && app.world.inventory.activeTool != ToolMode.Stockpile) return;
  auto ray = app.camera.castRay(sx, sy);
  int[3] wc;
  if(!app.getBestTile(ray, wc)) { app.world.inventory.paint.preview = []; app.syncBuildGhosts(); return; }
  app.world.inventory.paint.preview = [wc];
  app.syncBuildGhosts();
}

/** Update rectangular paint preview from anchor to current tile */
void updatePaintPreview(ref GameApp app, int[3] current) {
  if(app.world.inventory.paint.start == noTile) return;
  auto from = app.world.inventory.paint.start;
  app.world.inventory.paint.preview = [];
  int x0 = min(from[0], current[0]), x1 = max(from[0], current[0]);
  int z0 = min(from[2], current[2]), z1 = max(from[2], current[2]);
  for(int x = x0; x <= x1; x++) { for(int z = z0; z <= z1; z++) {
    app.world.inventory.paint.preview ~= [x, from[1], z];
  } }
  app.syncBuildGhosts();
}

/** Commit the current paint preview */
void commitPaint(ref GameApp app) {
  if(app.world.inventory.paint.preview.length == 0) return;
  final switch(app.world.inventory.activeTool) {
    case ToolMode.Select: break;
    case ToolMode.Build:
      foreach(tile; app.world.inventory.paint.preview) { app.placeTile(tile); }
      break;
    case ToolMode.Mine:
      foreach(tile; app.world.inventory.paint.preview) {
        if(app.world.getTileAt(tile) == ResourceType.None) continue;
        auto job = miningJob(tile);
        if(!app.tryAssign(job)) jobQueue ~= job;
      }
      break;
    case ToolMode.Stockpile:
      break; // TODO: designate stockpile zone
  }
  app.world.inventory.paint = PaintState.init;
  app.syncBuildGhosts();
}
