/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import block : ensureBlocks, loadBlocks, saveBlocks, syncBlockInstances;
import clouds : saveClouds, loadClouds;
import dwarf : saveDwarfs, spawnDwarf, loadDwarfs;
import feature : initFeatureMeshes;
import inventory : deriveInventory;
import io : ensureWorldDir;
import lattice : flatten, unflatten;
import orders : loadOrders, saveOrders;
import serialization : loadSections, saveSections;
import stockpile : saveStockpiles, loadStockpiles;
import vegetation : vegetationSection;
import water : saveWater, loadWater;

/** Register every world-save section once. Closures capture `app`; keys are stable strings. */
void registerPersistables(ref GameApp app) {
  if(app.persistables.length > 0) return;

  app.persistables ~= Persist.pod!(Diff!ResourceType)("diffs", () => flatten(app.world.data.diffs), (f) { app.world.data.diffs = unflatten(f); });
  app.persistables ~= Persist.pod!(Diff!ubyte)("water", () => app.world.saveWater(), (f) { app.world.loadWater(f); });
  app.persistables ~= Persist.pod!CloudDiff("clouds", () => app.world.saveClouds(), (f) { app.world.loadClouds(f); });
  app.persistables ~= Persist.pod!(EntityData!32)("dwarfs", () => app.saveDwarfs(), (f) { app.loadDwarfs(f); });
  app.persistables ~= Persist.pod!ubyte("stock", () => app.world.saveStockpiles(), (f) { app.world.loadStockpiles(f); });
  app.persistables ~= Persist.pod!Block("blocks", () => app.world.saveBlocks(), (f) { app.loadBlocks(f); });
  app.persistables ~= Persist.pod!Order("jobs", () => app.saveOrders(), (o) { app.loadOrders(o); });
  foreach(ref ftr; featureTable) app.persistables ~= vegetationSection(app, ftr.name);
}

/** Load the world from HDD */
void loadWorld(ref GameApp app) {
  ensureWorldDir();
  app.initFeatureMeshes();

  app.world.inventory.ghost = new GhostCube([app.world.tileSize, app.world.tileHeight]);
  app.objects ~= app.world.inventory.ghost;

  app.ensureBlocks();
  foreach(ref ft; featureTable) {
    if(ft.name !in app.world.vegetation.pending) app.world.vegetation.pending[ft.name] = null;
    if(ft.name !in app.world.vegetation) app.world.vegetation[ft.name] = null;
  }

  app.registerPersistables();
  auto blobs = loadSections(app.world.worldPath(), app.verbose > 0);
  foreach(ref p; app.persistables){ p.load(blobs); }

  if(app.world.dwarves is null || app.world.dwarves.dwarves.length == 0) { for(int x = 0; x <= 7; x++) app.spawnDwarf(); }

  app.deriveInventory();
  app.world.syncBlockInstances();
}

/** Save the world to HDD */
void saveWorld(ref GameApp app) {
  app.registerPersistables();
  Section[] all;
  foreach(ref p; app.persistables) all ~= p.save();
  saveSections(app.world.worldPath(), all, app.verbose > 0);
  if(app.verbose) SDL_Log("saveWorld: %d sections", cast(int)all.length);
}
