/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import entitywindow : entityGlyph, followEntity, needToggle;
import imgui : iconText;
import widgets : text;

/** Human-readable state label for an animal. */
string animalStatus(ref Animal a) {
  switch(a.state) {
    case EntityState.Wandering: return "Wandering";
    case EntityState.WaitingForPath: return a.hasJob ? format("Pathing -> %s", a.currentJob.name) : "Pathing";
    case EntityState.Moving: return a.hasJob ? format("Walking -> %s", a.currentJob.name) : "Walking";
    case EntityState.Working: return a.hasJob ? format("%s", a.currentJob.name) : "Working";
    case EntityState.Blocked: return "Blocked";
    default: return "Idle";
  }
}

/** One overview row: [glyph] species | tile - status + need bars. */
void showAnimalRow(ref GameApp app, Animals herd, size_t i, ref Animal a) {
  entityGlyph(a, cast(string)ICON_FA_PAW);
  igSameLine(0, 5);
  string species = entityTable[a.type].name;
  bool isSel = herd.selected == cast(int)i;
  if(igSelectable_Bool(cstr("%s##anm%d_%d", species, a.type, i), isSel, 0, ImVec2(0, 0))) {
    app.world.animals.selected = -1;   // single container, single selection
    herd.selected = cast(int)i;
  }
  igSameLine(0, 5);
  text("%s - %s  H:%.0f T:%.0f", a.tile, animalStatus(a), a.hunger * 100.0f, a.thirst * 100.0f);
}

/** Detailed sheet for the selected animal. */
void showAnimalSheet(ref GameApp app, Animals herd, ref Animal a, int selected) {
  entityGlyph(a, cast(string)ICON_FA_PAW); igSameLine(0, 5);
  string species = entityTable[a.type].name;
  if(igSelectable_Bool(cstr("%s##anmfollow", species), false, 0, ImVec2(0, 0))) { app.followEntity(a.uid, herd); }
  text("Tile: %s", a.tile);
  needToggle("Hunger", "hungry", a.needs[Need.Hunger], "anm_hunger");
  needToggle("Thirst", "thirsty", a.needs[Need.Thirst], "anm_thirst");
  text("Job: %s", a.hasJob ? a.currentJob.name : "None");
}

/** Top level: one row per species present, with a live count; click to drill in. */
void showSpeciesList(ref GameApp app) {
  auto herd = app.world.animals;
  if(herd is null) { text("No animals"); return; }
  size_t[entityTable.length] counts = 0;
  int idle, walking, working; size_t total;
  foreach(ref a; herd.animals) {
    total++; counts[a.type]++;
    switch(a.state) {
      case EntityState.Idle: idle++; break;
      case EntityState.Moving: case EntityState.Wandering: walking++; break;
      case EntityState.Working: working++; break;
      default: break;
    }
  }
  foreach(t; 0 .. entityTable.length) {
    if(counts[t] == 0) continue;
    if(igSelectable_Bool(cstr("%s  %s  x%d##sp%d", cast(string)ICON_FA_PAW, entityTable[t].name, counts[t], cast(int)t), false, 0, ImVec2(0, 0))) {
      herd.selected = -1;
      herd.selectedType = cast(int)t;
    }
  }
  text("Animals: %d | Idle: %d | Moving: %d | Feeding: %d", total, idle, walking, working);
}

/** Second level: every animal of the drilled-in species. */
void showSpeciesMembers(ref GameApp app, Animals herd, int type) {
  if(igButton(iconText(cast(string)ICON_FA_ARROW_LEFT, "Back##SMember"), ImVec2(0,0))) { herd.selectedType = -1; return; }
  text("%s", entityTable[type].name);
  igSeparator();
  foreach(i, ref a; herd.animals) {
    if(cast(int)a.type != type) continue;
    app.showAnimalRow(herd, i, a);
  }
}

void showAnimalContent(ref GameApp app, uint font = 0) {
  igSeparator();
  auto herd = app.world.animals;
  if(herd is null) { app.showSpeciesList(); return; }
  if(herd.selected >= 0 && herd.selected < cast(int)herd.animals.length) {
    if(igButton(iconText(cast(string)ICON_FA_ARROW_LEFT, "Back##SOverview"), ImVec2(0,0))) { herd.selected = -1; return; }
    app.showAnimalSheet(herd, herd.animals[herd.selected], herd.selected);
    return;
  }
  if(herd.selectedType >= 0 && herd.selectedType < cast(int)entityTable.length) {
    app.showSpeciesMembers(herd, herd.selectedType);
    return;
  }
  app.showSpeciesList();
}
