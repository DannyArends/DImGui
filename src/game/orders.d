/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import jobs : buildingJob, interactFeatureJob, miningJob, jobQueue;

/** Player-issued order kinds that persist. Extend (e.g. Craft) as needed */
enum OrderKind : ubyte { Mine, Build, InteractFeature }

/** POD projection of a player order: enough to replay its factory on load */
struct Order {
  OrderKind kind;
  int[3] tile;
  ResourceType tileType;   // Build only
}

/** Map a queued Job back to a persistable Order; returns false for non-player/transient jobs */
bool orderOf(const Job!Dwarf j, out Order o) {
  switch(j.name) {
    case "Mining": o = Order(OrderKind.Mine, j.targetTile); return true;
    case "InteractFeature": o = Order(OrderKind.InteractFeature, j.targetTile); return true;
    case "Building": o = Order(OrderKind.Build, j.targetTile, j.buildType); return true;
    default: return false;
  }
}

/** Rebuild a live Job (with its behaviour) from a persisted Order */
Job!Dwarf jobOf(const Order o) {
  final switch(o.kind) {
    case OrderKind.Mine: return miningJob(o.tile);
    case OrderKind.Build: return buildingJob(o.tile, o.tileType);
    case OrderKind.InteractFeature: return interactFeatureJob(o.tile);
  }
}

/** Collect all persistable player orders from the queue and every dwarf's in-flight stack */
Order[] saveOrders(ref GameApp app) {
  Order[] orders;
  Order o;
  foreach(ref j; jobQueue) if(orderOf(j, o)) orders ~= o;
  if(app.world.dwarves !is null){ foreach(ref d; app.world.dwarves.dwarves) {
    foreach(ref j; d.jobStack){ if(orderOf(j, o)){ orders ~= o; } }
  } }
  return orders;
}

/** Replay persisted orders back into the queue; existing isValid/pruneJobQueue cull any now-invalid. */
void loadOrders(ref GameApp app, Order[] orders) {
  foreach(ref o; orders){ jobQueue ~= jobOf(o); }
  SDL_Log("loadJobs: %d orders", cast(int)orders.length);
}
