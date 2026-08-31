/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : noBlock;
import ghost : syncBuildGhosts;
import inventory : deriveInventory;
import jobs : jobQueue, placeTileJob, pinnedPickup, cleanWorksiteJob;
import resources : hasShape, matchDemand;
import workshop : buildWorkshopJob;
import stockpile : storedTileOf;
import textures : ImTextureRefFromID, idx;
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

/** The ingredient the window is filling right now: the need of the first unassigned slot. */
private Ingredient currentNeed(ref GameApp app) {
  foreach(ref b; app.world.inventory.buildSelection) if(b.blockID == noBlock) return b.need;
  return Ingredient.init;
}

private Cand[][ResourceType] buildCandidates(ref GameApp app) {
  Cand[][ResourceType] groups;
  auto rt = app.refTile();
  auto need = app.currentNeed();
  bool anyBuildable = (need.cls == Substance.None && need.item == ItemTemplate.None);   // landscaping
  foreach(id, ref b; app.world.drops) {
    if(b.reserved || b.item.hasShape) continue;
    bool ok = anyBuildable ? resourceTable[b.item.material].buildable : b.item.matchDemand(need.cls, need.item);
    if(!ok) continue;
    int[3] at = (b.tile == storedTile) ? app.world.storedTileOf(id) : b.tile;
    if(at == noTile || at == builtTile) continue;                 // carried / consumed / unresolved
    groups[b.item.material] ~= Cand(id, manhattan(at, rt));
  }
  foreach(m, ref list; groups) list.sort!((a, c) => a.dist < c.dist);
  return groups;
}

/** Assign the nearest not-yet-chosen block of this group to the next tile. */
private void pickNearest(ref GameApp app, Cand[] list) {
  foreach(ref c; list) if(!app.chosen(c.id)) { app.pick(c.id); return; }
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
  if(app.world.inventory.placingWorkshop.length) {
    auto tile = app.world.inventory.buildSelection[0].tile;
    Job!Dwarf[] fetch = [cleanWorksiteJob(tile)];
    foreach(ref b; app.world.inventory.buildSelection) {
      if(b.blockID == noBlock) continue;
      auto p = b.blockID in app.world.drops;
      if(p is null) continue;
      int[3] at = (p.tile == storedTile) ? app.world.storedTileOf(b.blockID) : p.tile;
      fetch ~= pinnedPickup(b.blockID, at, p.item.material);
    }
    jobQueue ~= buildWorkshopJob(app.world.inventory.placingWorkshop, tile, fetch);
  } else {
    foreach(ref b; app.world.inventory.buildSelection) {
      if(b.blockID == noBlock) continue;
      auto p = b.blockID in app.world.drops;
      if(p is null) continue;
      jobQueue ~= placeTileJob(b.tile, b.blockID, p.tile, p.item.material);
    }
  }
  app.world.inventory.buildSelection = [];
  app.world.inventory.showBuildWindow = false;
  app.deriveInventory();
  app.syncBuildGhosts();
}

/** Cancel: drop the whole pending selection without queueing. */
void cancelBuild(ref GameApp app) {
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
  igSetNextWindowSize(ImVec2(app.gui.io.DisplaySize.x * 0.35f, 0), ImGuiCond_Appearing);

  auto need = app.currentNeed();
  int needed = 0;
  foreach(ref b; app.world.inventory.buildSelection) if(b.blockID == noBlock && b.need == need) needed++;

  string what = (need.item != ItemTemplate.None) ? itemTemplateTable[need.item].name : (need.cls  != Substance.None) ? to!string(need.cls) : "material";

  igBegin("Select materials##buildsel".toStringz, &app.world.inventory.showBuildWindow, 0);
  text("Select %s  (%d needed)", what, needed);

  auto groups = app.buildCandidates();
  float btnCol = igGetWindowWidth() - app.gui.fontsize * 5.5f;   // right-aligned button column
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, ImVec2(4.0f, 0.0f));   // buttons as tall as the text
  foreach(m, ref list; groups) {
    igPushID_Int(cast(int)m); scope(exit) igPopID();
    int avail = 0, picked = 0, nearest = 0;
    foreach(ref c; list) { if(app.chosen(c.id)) { picked++; } else { if(avail == 0) { nearest = c.dist; } avail++; } }

    auto texIdx = idx(app.textures, resourceTable[m].textures.texOf("2D"));
    auto imTex = ImTextureRefFromID((texIdx >= 0)? cast(ulong)app.textures[texIdx].imID : -1);
    if(texIdx >= 0) { igImage(imTex, ImVec2(app.gui.fontsize, app.gui.fontsize), ImVec2(0,0), ImVec2(1,1)); igSameLine(0, 4); }

    auto lbl = cstr("%s  avail:%d  picked:%d  Dist:%d###g%d", resourceTable[m].name, avail, picked, nearest, cast(int)m);
    bool open = igTreeNodeEx_Str(lbl, ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_OpenOnDoubleClick);
    if(igIsItemClicked(0) && !igIsItemToggledOpen()) app.pickNearest(list);   // name = assign one; arrow = expand only

    igSameLine(btnCol, 0);
    if(igButton("All", ImVec2(0, 0))) { foreach(ref c; list) { app.pick(c.id); } }
    igSameLine(0, 4);
    if(picked == 0) igPushStyleVar_Float(ImGuiStyleVar_Alpha, 0.4f);
    if(igButton("None", ImVec2(0, 0)) && picked > 0) app.clearMaterial(m);
    if(picked == 0) igPopStyleVar(1);

    if(open) foreach(ref c; list) {
      igPushID_Int(cast(int)c.id); scope(exit) igPopID();
      if(texIdx >= 0) { igImage(imTex, ImVec2(app.gui.fontsize, app.gui.fontsize), ImVec2(0,0), ImVec2(1,1)); igSameLine(0, 4); }
      bool isPicked = app.chosen(c.id);
      if(igSelectable_Bool(cstr("%s  Dist: %d##i%d", resourceTable[m].name, c.dist, cast(int)c.id), isPicked, 0, ImVec2(0, 0)) && !isPicked) app.pick(c.id);
    }
    if(open) igTreePop();
  }
  igPopStyleVar(1);

  igNewLine();

  if(igButton("Cancel".toStringz, ImVec2(0, 0))) app.cancelBuild();

  if(needed == 0 && app.world.inventory.buildSelection.length > 0) app.commitBuild();

  igEnd();
  igPopFont();
}