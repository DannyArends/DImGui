/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import boundingbox : computeBoundingBox;
import camera : castRay, tryDrag, tryZoom;
import chunk : getBestTile;
import geometry : setColor;
import ghost : updateGhostTile, syncBuildGhosts;
import intersection : intersects;
import inventory : placeTile, computeDragPreview;
import jobs : tryAssign, jobQueue, miningJob, interactFeatureJob;
import line : createLine;
import vegetation : getBestVegetation;

/** Handle mouse events */
void handleMouseEvents(ref App app, SDL_Event e) {
  app.camera.lastMousePos = [app.gui.io.MousePos.x, app.gui.io.MousePos.y];
  auto ray = app.camera.castRay(app.camera.lastMousePos[0], app.camera.lastMousePos[1]);

  if(e.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
    if (e.button.button == SDL_BUTTON_LEFT) { 
      app.camera.isdrag[0] = true;
      app.camera.lastMousePos = [e.button.x, e.button.y];
      if(app.world.inventory.ghost.tile != noTile && app.world.inventory.ghost.type != ResourceType.None) {
        app.world.inventory.isDragging = true;
        app.world.inventory.dragPreview = [app.world.inventory.ghost.tile];
        app.syncBuildGhosts();
      }
    }
    if (e.button.button == SDL_BUTTON_RIGHT) { 
      app.camera.isdrag[1] = true;
      app.world.inventory.ghost.type = ResourceType.None;
      app.camera.lastMousePos = [e.button.x, e.button.y];
    }
  }
  if(e.type == SDL_EVENT_MOUSE_BUTTON_UP) {
    app.camera.isdrag[0] = false; 
    if (e.button.button == SDL_BUTTON_LEFT) {
      if(app.world.inventory.isDragging) {
        foreach(tile; app.world.inventory.dragPreview) app.placeTile(tile);
        app.world.inventory.isDragging = false;
        app.world.inventory.dragPreview = [];
        app.syncBuildGhosts();
      } else if(app.world.inventory.ghost.tile != noTile) {
        app.placeTile(app.world.inventory.ghost.tile);
      } else {
        auto hits = app.getHits(ray, app.showRays);
        if(hits.length > 0) {
          int[3] wc;
          Job job;
          if(app.getBestTile(ray, wc)) { job = miningJob(wc); }
          foreach(ref ft; features) {
            bool matchFeature(string g) { return ft.parts.any!(p => p.mesh == g); }
            if(app.getBestVegetation!(Feature, matchFeature)(ray, hits, app.world.features.get(ft.name, null), wc)) {
              job = interactFeatureJob(wc);
              break;
            }
          }
          if(job.name !is null && !app.tryAssign(job)) jobQueue ~= job;
        }
        foreach (ref hit; hits) {
          auto obj = app.objects[hit.idx[0]];
          if (cast(Chunk)obj is null) {
            obj.box.setColor(Colors.yellowgreen);
            obj.window = true;
            break;
          }
        }
      }
    }
    if (e.button.button == SDL_BUTTON_RIGHT) { app.camera.isdrag[1] = false; }
    app.updateGhostTile(ray);
  }
  if(e.type == SDL_EVENT_MOUSE_MOTION){ 
    if(app.camera.isdrag[1]) { app.tryDrag(e.motion.xrel, e.motion.yrel); }
    app.updateGhostTile(ray);
    if(app.world.inventory.isDragging && app.world.inventory.ghost.tile != noTile && app.world.inventory.dragPreview.length > 0) {
      app.computeDragPreview(app.world.inventory.dragPreview[0], app.world.inventory.ghost.tile);
      app.syncBuildGhosts();
    }
  }
  if(e.type == SDL_EVENT_MOUSE_WHEEL){ app.tryZoom(-e.wheel.y); }
}

/** Get a list of intersections between the ray and the objects in the scene */
Intersection[] getHits(ref App app, float[3][2] ray, bool showRay = true){
  Intersection[] hits;

  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isVisible) continue;                       // Invisible objects should not generate hits
    if(!app.objects[x].isSelectable) continue;                    // Non-selectable objects should not generate hits
    if(cast(Line)(app.objects[x]) !is null) continue;             // Lines should not generate hits
    app.objects[x].computeBoundingBox(app.trace);                 // Make sure we compute the current Bounding Box
    auto intersections = ray.intersects(app.objects[x].box, x);   // Compute the intersection
    app.objects[x].window = false;
    if (intersections.any!(i => i.intersects)) {
      //version(Android) {} else { app.gui.showObjects = true; }
      hits ~= intersections;
    } else { app.objects[x].box.setColor(); }
  }
  if(showRay) app.objects ~= createLine(ray);
  hits.sort!("a.tmin < b.tmin");
  return(hits);
}
