/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : noBlock;
import ghost : syncBuildGhosts;
import inventory : deriveInventory;
import jobs : jobQueue, placeTileJob;
import resources : hasShape;
import vector : manhattan;
import widgets : text;

/** A candidate block for a build slot: its id and distance to the reference tile. */
private struct Cand { uint id; int dist; }

/** Reference tile for distances: the drag-start (first painted) tile of the run. */
private int[3] refTile(ref GameApp app) {
  return app.world.inventory.buildSelection.length ? app.world.inventory.buildSelection[0].tile : noTile;
}

/** Index of the next tile still awaiting a block, or -1 when all are assigned. */
private long nextSlot(ref GameApp app) {
  foreach(i, ref b; app.world.inventory.buildSelection) if(b.blockID == noBlock) return i;
  return -1;
}

/** True if block `id` is already chosen for some tile in this selection. */
private bool chosen(ref GameApp app, uint id) {
  foreach(ref b; app.world.inventory.buildSelection) if(b.blockID == id) return true;
  return false;
}

/** Unreserved, unchosen buildable raw blocks grouped by material, each list sorted nearest-first. */
private Cand[][ResourceType] buildCandidates(ref GameApp app) {
  Cand[][ResourceType] groups;
  auto rt = app.refTile();
  foreach(id, ref b; app.world.drops) {
    if(b.reserved || b.item.hasShape) continue;
    if(!resourceTable[b.item.material].buildable) continue;
    groups[b.item.material] ~= Cand(id, manhattan(b.tile, rt));
  }
  foreach(m, ref list; groups) list.sort!((a, c) => a.dist < c.dist);
  return groups;
}

/** Assign block `id` to the next unassigned tile. */
private void pick(ref GameApp app, uint id) {
  if(app.chosen(id)) return;
  auto i = app.nextSlot(); if(i < 0) return;
  app.world.inventory.buildSelection[i].blockID = id;
  app.syncBuildGhosts();
}

/** Clear every tile assigned a block of material `m`. */
private void clearMaterial(ref GameApp app, ResourceType m) {
  foreach(ref b; app.world.inventory.buildSelection) {
    if(b.blockID == noBlock) continue;
    if(auto p = b.blockID in app.world.drops) if(p.item.material == m) b.blockID = noBlock;
  }
  app.syncBuildGhosts();
}

/** Queue one pinned placement job per assigned tile, then close. */
private void commitBuild(ref GameApp app) {
  foreach(ref b; app.world.inventory.buildSelection) {
    if(b.blockID == noBlock) continue;
    auto p = b.blockID in app.world.drops;
    if(p is null) continue;
    jobQueue ~= placeTileJob(b.tile, b.blockID, p.tile, p.item.material);
  }
  app.world.inventory.buildSelection = [];
  app.world.inventory.showBuildWindow = false;
  app.deriveInventory();
  app.syncBuildGhosts();
}

/** Cancel: drop the whole pending selection without queueing. */
private void cancelBuild(ref GameApp app) {
  app.world.inventory.buildSelection = [];
  app.world.inventory.showBuildWindow = false;
  app.syncBuildGhosts();
}

/** DF-style material picker: choose a specific block for each tile of the current build. */
void showBuildContent(ref GameApp app, uint font = 0) {
  if(!app.world.inventory.showBuildWindow) return;

  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  float dispW = app.gui.io.DisplaySize.x, dispH = app.gui.io.DisplaySize.y;
  igSetNextWindowPos(ImVec2(dispW * 0.5f, dispH * 0.5f), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));

  int needed = 0;
  foreach(ref b; app.world.inventory.buildSelection) if(b.blockID == noBlock) needed++;

  igBegin("Select materials##buildsel".toStringz, &app.world.inventory.showBuildWindow, 0);
  text("Amount needed: %d", needed);

  auto groups = app.buildCandidates();
  if(igBeginTable("mats##buildsel", 3, ImGuiTableFlags_SizingFixedFit, ImVec2(0, 0), 0.0f)) {
    foreach(m, ref list; groups) {
      igPushID_Int(cast(int)m); scope(exit) igPopID();
      igTableNextRow(0, 0.0f);
      igTableNextColumn();
        bool open = igTreeNodeEx_Str(cstr("%s [%d]  Dist: %d", resourceTable[m].name, cast(int)list.length, list.length ? list[0].dist : 0),
                      ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_OpenOnDoubleClick);
      igTableNextColumn();
        if(igButton("All", ImVec2(0, 0))) foreach(ref c; list) app.pick(c.id);
      igTableNextColumn();
        if(igButton("None", ImVec2(0, 0))) app.clearMaterial(m);
      if(open) {
        foreach(ref c; list) {
          igPushID_Int(cast(int)c.id); scope(exit) igPopID();
          igTableNextRow(0, 0.0f);
          igTableNextColumn();
            igText(cstr("  Dist: %d%s", c.dist, app.chosen(c.id) ? "  (picked)" : ""));
          igTableNextColumn();
            if(!app.chosen(c.id) && igButton("Use", ImVec2(0, 0))) app.pick(c.id);
          igTableNextColumn();
        }
        igTreePop();
      }
    }
    igEndTable();
  }

  igNewLine();
  if(igButton("Cancel".toStringz, ImVec2(0, 0))) app.cancelBuild();

  if(needed == 0 && app.world.inventory.buildSelection.length > 0) app.commitBuild();

  igEnd();
  igPopFont();
}