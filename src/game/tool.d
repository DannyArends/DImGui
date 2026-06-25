/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import camera : castRay;
import chunk : getBestTile;
import ghost : getGhostTile, syncBuildGhosts;
import feature : hasFeature;
import inventory : placeTile, computeDragPreview;
import jobs : tryAssign, jobQueue, miningJob, interactFeatureJob;
import hits : getHits;
import gameobjects : PendingBuild;
import geometry : setColor;
import stockpile : createStockpile;
import tile : tileToWorld, getTileAt, tileAbove, getWater, setWater, tileBelow;
import matrix : translateScale;
import vegetation : getBestVegetation;
import water : WATER_MAX;

enum ToolMode : ubyte { Info, Select, Mine, Interact, Build, Stockpile, Water }
enum ToolKind : ubyte { Query, RayPaint, BuildPaint }

struct Tool {
  ToolMode mode;                                    /// ToolMode
  string icon;                                      /// FontAwesome glyph
  float[4] color;                                   /// Highlight & Preview color
  Matrix function(float[3], float, float) matrix;   /// Matrix builder
  ToolKind kind;                                    /// Dispatch mechanism
  void function(ref GameApp, int[3]) commit;        /// Per-tile commit action (null = none
  bool solidAnchor;                                 /// true = target the solid hit cell
}

immutable float os = 1.05f;
immutable float flat = 0.02f;

// TODO: Fold tool.d buildPress/buildDrag into paintPress/paintDrag

Matrix mineHighlight(float[3] wp, float ts, float th) { return translateScale([wp[0], wp[1], wp[2]], [ts*os, th*os, ts*os]); }
Matrix interactHighlight(float[3] wp, float ts, float th) { return translateScale([wp[0], wp[1], wp[2]], [ts, th, ts]); }
Matrix buildHighlight(float[3] wp, float ts, float th) { return translateScale([wp[0], wp[1], wp[2]], [ts, th, ts]); }
Matrix stockpileHighlight(float[3] wp, float ts, float th) { return translateScale([wp[0], wp[1] + 0.5f * th, wp[2]], [ts*os, th*flat, ts*os]); }
Matrix waterHighlight(float[3] wp, float ts, float th) { return translateScale([wp[0], wp[1], wp[2]], [ts*os, th*os, ts*os]); }

void mineCommit(ref GameApp app, int[3] tile) {
  if(app.world.getTileAt(tile) == ResourceType.None) return;
  auto job = miningJob(tile);
  if(!app.tryAssign(job)) jobQueue ~= job;
}

void interactCommit(ref GameApp app, int[3] tile) {
  if(!app.hasFeature(tile, "Fell") && !app.hasFeature(tile, "Gather")) return;
  auto job = interactFeatureJob(tile);
  if(!app.tryAssign(job)) jobQueue ~= job;
}

void waterCommit(ref GameApp app, int[3] tile) {
  if(app.world.getTileAt(tile) != ResourceType.None) return;
  ubyte cur = cast(ubyte)app.getWater(tile);
  app.setWater(tile, cast(ubyte)min(WATER_MAX, cur + 3));
}

void openBuildSelection(ref GameApp app) {
  if(app.world.inventory.paint.preview.length == 0) return;
  app.world.inventory.buildSelection = [];
  foreach(t; app.world.inventory.paint.preview) app.world.inventory.buildSelection ~= PendingBuild(t);
  app.world.inventory.showBuildWindow = true;
  app.world.inventory.paint = PaintState.init;
  app.syncBuildGhosts();
}

immutable Tool[] tools = [
  Tool(ToolMode.Info, cast(string)ICON_FA_MAGNIFYING_GLASS, Colors.black, null, ToolKind.Query, null),
  Tool(ToolMode.Select, cast(string)ICON_FA_ARROW_POINTER, Colors.hotpink, null, ToolKind.Query, null),
  Tool(ToolMode.Mine, cast(string)ICON_FA_PERSON_DIGGING, Colors.orangered, &mineHighlight, ToolKind.RayPaint, &mineCommit, true),
  Tool(ToolMode.Interact, cast(string)ICON_FA_TREE, Colors.forestgreen, &interactHighlight, ToolKind.RayPaint, &interactCommit, false),
  Tool(ToolMode.Build, cast(string)ICON_FA_TROWEL, Colors.dodgerblue, &buildHighlight, ToolKind.BuildPaint, null, false),
  Tool(ToolMode.Stockpile, cast(string)ICON_FA_WAREHOUSE, Colors.gold, &stockpileHighlight,ToolKind.RayPaint, null, true),
  Tool(ToolMode.Water, cast(string)ICON_FA_WATER, Colors.dodgerblue, &waterHighlight, ToolKind.RayPaint, &waterCommit, false),
];

/** Info: pick a dwarf/object for the sidebar */
void infoPress(ref GameApp app, float[3][2] ray) {
  auto hits = app.getHits(ray, app.showRays);
  if(hits.length == 0) return;
  app.world.dwarves.selected = -1;
  foreach(ref hit; hits) {
    if(app.objects[hit.idx[0]] is app.world.dwarves) {
      if(hit.idx[1] < app.world.dwarves.dwarves.length) app.world.dwarves.selected = cast(int)hit.idx[1];
      break;
    }
  }
  app.selectObject(hits);
}

/**  Select: click-designate mine/interact (no object selection) */
void selectPress(ref GameApp app, float[3][2] ray) {
  int[3] wc;
  auto hits = app.getHits(ray, app.showRays);
  Job job;
  if(app.getBestTile(ray, wc)) job = miningJob(wc);
  foreach(ref ft; features) {
    bool matchFeature(string g) { return ft.parts.any!(p => g == ft.name ~ ":" ~ p.mesh); }
    if(app.getBestVegetation!(Feature, matchFeature)(ray, hits, app.world.features.get(ft.name, null), wc)) {
      job = interactFeatureJob(wc); break;
    }
  }
  if(job.name !is null) app.tryAssign(job);
}

void buildPress(ref GameApp app) {
  if(app.world.inventory.tile == noTile) return;
  app.world.inventory.paint.active = true;
  app.world.inventory.paint.start = app.world.inventory.tile;
  app.world.inventory.paint.preview = [app.world.inventory.tile];
  app.syncBuildGhosts();
}

void buildDrag(ref GameApp app) {
  if(!app.world.inventory.paint.active || app.world.inventory.tile == noTile) return;
  app.computeDragPreview(app.world.inventory.paint.start, app.world.inventory.tile);
  app.syncBuildGhosts();
}

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

/** Begin a rectangular paint at the hovered tile (designation & zone tools) */
void paintPress(ref GameApp app, float[3][2] ray) {
  if(app.world.inventory.tile == noTile) return;
  app.world.inventory.paint.active = true;
  app.world.inventory.paint.start = app.world.inventory.tile;
  app.world.inventory.paint.preview = [app.world.inventory.tile];
  app.syncBuildGhosts();
}

/** Extend the rectangular paint to the hovered tile */
void paintDrag(ref GameApp app, float[3][2] ray) {
  if(!app.world.inventory.paint.active) return;
  if(app.world.inventory.tile == noTile) return;
  app.updatePaintPreview(app.world.inventory.tile);   // same cell the hover ghost used
}

/** Primary press: left click / single tap */
void handlePrimaryPress(ref GameApp app, float sx, float sy) {
  auto ray = app.camera.castRay(sx, sy);
  final switch(tools[app.world.inventory.activeTool].kind) {
    case ToolKind.Query: (app.world.inventory.activeTool == ToolMode.Info)?app.infoPress(ray): app.selectPress(ray); break;
    case ToolKind.RayPaint: app.paintPress(ray); break;
    case ToolKind.BuildPaint: app.buildPress(); break;
  }
}

/** Primary drag: left hold + move / single finger move */
void handlePrimaryDrag(ref GameApp app, float sx, float sy) {
  auto ray = app.camera.castRay(sx, sy);
  final switch(tools[app.world.inventory.activeTool].kind) {
    case ToolKind.Query: break;
    case ToolKind.RayPaint: app.paintDrag(ray); break;
    case ToolKind.BuildPaint: app.buildDrag();    break;
  }
}

/** Primary release: left up / finger up */
void handlePrimaryRelease(ref GameApp app, float sx, float sy) {
  final switch(tools[app.world.inventory.activeTool].kind) {
    case ToolKind.Query: break;
    case ToolKind.RayPaint:
      if(app.world.inventory.activeTool == ToolMode.Stockpile){
        app.createStockpile(app.world.inventory.paint.preview);
        app.world.inventory.paint = PaintState.init;
        app.syncBuildGhosts();
      }else if(app.world.inventory.paint.active){ app.commitPaint(); }
    break;
    case ToolKind.BuildPaint: if(app.world.inventory.paint.active) app.openBuildSelection(); break;
  }
}

/** Secondary press: right click */
void handleSecondaryPress(ref GameApp app, float sx, float sy) { }

/** Secondary press: right click */
void handleSecondaryRelease(ref GameApp app, float sx, float sy) {
  app.world.inventory.paint = PaintState.init;
  app.world.inventory.type = ResourceType.None;
  app.world.inventory.activeTool = ToolMode.Select;
  app.syncBuildGhosts();
}

void updateHoverHighlight(ref GameApp app, float[3][2] ray) {
  auto t = tools[app.world.inventory.activeTool];
  if(t.kind == ToolKind.Query) return;
  int[3] wc; bool ok;
  if(t.solidAnchor){
    ok = app.getBestTile(ray, wc);
  } else { wc = app.getGhostTile(ray, app.getHits(ray, false)); ok = (wc != noTile); }
  app.world.inventory.tile = ok ? wc : noTile;
  if(!app.world.inventory.paint.active) app.world.inventory.paint.preview = ok ? [wc] : [];
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
  auto commit = tools[app.world.inventory.activeTool].commit;
  if(commit !is null) foreach(tile; app.world.inventory.paint.preview) commit(app, tile);
  app.world.inventory.paint = PaintState.init;
  app.syncBuildGhosts();
}
