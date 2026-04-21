/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;
import geometry;
import search : performSearch, atGoal, stepThroughPath;
import world : setTile, tileToWorld, isTileOccupied;
import vector : euclidean;
import tileatlas : tileData;
import block : spawnDroppedBlock;
import pathfinding : followPath, pathfindTo, findGoalTile;
import jobs : BuildJob, miningQueue, buildQueue, claimJob, claimBuildJob, doPickup, doBuilding, doMining;

/** Dwarven Cylinderz  */
class Dwarf : Cylinder {
  string name;                              /// Name
  int[3] tile = [0, 0, 0];                  /// Which tile we're on
  int[3] pickupTile = [int.min, 0, 0];      /// Dropped block to pick up
  int[3] targetTile = [int.min, 0, 0];      /// Where we are going
  float[3][] path;                          /// Path we're on
  float miningProgress = 0.0f;              /// Mining progress
  BuildJob currentBuild;                    /// Active build job
  float[3] visualPos = [0.0f, 0.0f, 0.0f];  /// Current interpolated position
  float[3] moveFrom = [0.0f, 0.0f, 0.0f];   /// World pos at start of move
  float[3] moveTo = [0.0f, 0.0f, 0.0f];     /// World pos at end of move
  float moveT = 1.0f;                       /// 1.0 = arrived, 0.0 = just started

  this() {
    geometry = (){ return(typeof(this).stringof); };
  }
}

/** Random names */
string randomDwarfName() {
  string[] prefixes = ["Urist", "Iden", "Meng", "Reg", "Doren", "Ast", "Nil", "Erib", "Thob", "Cog"];
  string[] suffixes = ["ral", "dor", "zan", "kel", "tok", "mis", "bur", "ith", "gar", "lon"];
  return prefixes[uniform(0, prefixes.length)] ~ suffixes[uniform(0, suffixes.length)];
}

/** Find a free surface tile (as in non-occupado) and on top of the world */
int[3] findFreeSurfaceTile(ref App app, int startX = 0, int startZ = 0) {
  foreach(radius; 0..app.world.chunkSize) {
    for(int x = -radius; x <= radius; x++) {
      for(int z = -radius; z <= radius; z++) {
        int[3] tile = [startX + x, app.world.chunkHeight-1, startZ + z];
        while(tile[1] > 0) {
          TileType tt = app.world.getTileAt(tile);
          if(tt != TileType.None) break;
          tile[1]--;
        }
        if(tile[1] > 0 && !app.isTileOccupied([tile[0], tile[1]+1, tile[2]])) { return [tile[0], tile[1]+1, tile[2]]; }
      }
    }
  }
  return [int.min, 0, 0];
}

/** dwarfFrame */
void dwarfFrame(ref App app, ref Geometry obj, float dt) {
  auto d = cast(Dwarf)obj;
  if (d is null || d.moveT >= 1.0f) return;
  d.moveT = min(1.0f, d.moveT + dt * 2.0f);
  float t = d.moveT * d.moveT * (3.0f - 2.0f * d.moveT);
  d.visualPos = [
    d.moveFrom[0] + t * (d.moveTo[0] - d.moveFrom[0]),
    d.moveFrom[1] + t * (d.moveTo[1] - d.moveFrom[1]),
    d.moveFrom[2] + t * (d.moveTo[2] - d.moveFrom[2])
  ];
  d.position(d.visualPos);
  if (d.moveT >= 1.0f && d.path.length > 0) { app.followPath(d); }
}

/** dwarfTick */
void dwarfTick(ref App app, ref Geometry obj) {
  auto d = cast(Dwarf)obj;
  if(d is null) return;
  if(d.targetTile[0] == int.min) {
    if(d.currentBuild.tileType != TileType.None && d.pickupTile[0] == int.min) {
      d.targetTile = d.currentBuild.tile;
      auto goalTile = app.findGoalTile(d);
      if(goalTile[0] == int.min || !app.pathfindTo(d, goalTile)) {
        app.spawnDroppedBlock(d.tile, d.currentBuild.tileType);
        buildQueue ~= d.currentBuild;
        d.currentBuild = BuildJob.init;
        d.targetTile = [int.min, 0, 0];
      }
    } else if(!app.claimJob(d)) { app.claimBuildJob(d); }
  } else if(d.path.length > 0 && d.moveT >= 1.0f) {
    app.followPath(d);
  } else if(d.path.length == 0 && d.moveT >= 1.0f) {
    if(d.pickupTile[0] != int.min) app.doPickup(d);
    else if(d.currentBuild.tileType != TileType.None) app.doBuilding(d);
    else app.doMining(d);
  }
}

/** Spawn a Dwarf */
void spawnDwarf(ref App app, string name) {
  auto tile = app.findFreeSurfaceTile();
  if(tile[0] == int.min) return;
  Dwarf dwarf = new Dwarf();
  dwarf.name = name;
  dwarf.tile = tile;
  auto wp = app.tileToWorld(tile);
  dwarf.position([wp[0], wp[1] - 0.5f, wp[2]]);
  dwarf.visualPos = [wp[0], wp[1] - 0.5f, wp[2]];
  dwarf.moveFrom  = dwarf.visualPos;
  dwarf.moveTo = dwarf.visualPos;
  dwarf.moveT = 1.0f;
  dwarf.setColor([uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), uniform(0.3f, 1.0f), 1.0f]);
  dwarf.onFrame = &dwarfFrame;
  dwarf.onTick = &dwarfTick;
  app.objects ~= dwarf;
}

