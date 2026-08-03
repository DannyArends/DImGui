/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import imgui : faIcon, iconText;
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

/** Coloured paw glyph. */
void animalGlyph(ref Animal a) {
  igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(a.color[0], a.color[1], a.color[2], a.color[3]));
  text("%s", fromStringz(faIcon(cast(string)ICON_FA_PAW)));
  igPopStyleColor(1);
}

/** One overview row: [glyph] species | tile - status + need bars. */
void showAnimalRow(ref GameApp app, size_t i, ref Animal a) {
  animalGlyph(a);
  igSameLine(0, 5);
  string species = animalTable[a.type].name;
  bool isSel = app.world.animals.selected == cast(int)i;
  if(igSelectable_Bool(cstr("%s##anm%d", species, i), isSel, 0, ImVec2(0, 0))) { app.world.animals.selected = cast(int)i; }
  igSameLine(0, 5);
  text("%s - %s  H:%.0f T:%.0f", a.tile, animalStatus(a), a.hunger * 100.0f, a.thirst * 100.0f);
}

/** Camera follow for the selected animal. */
void followAnimal(ref GameApp app, uint uid) {
  app.camera.onFrame = (dt) {
    foreach(ref x; app.world.animals.animals){ if(x.uid == uid) { app.camera.lookat = x.visualPos; app.camera.isDirty = true; return; } }
    app.camera.onFrame = null;
  };
}

/** Detailed sheet for the selected animal. */
void showAnimalSheet(ref GameApp app, ref Animal a, int selected) {
  animalGlyph(a); igSameLine(0, 5);
  string species = animalTable[a.type].name;
  if(igSelectable_Bool(cstr("%s##anmfollow", species), false, 0, ImVec2(0, 0))) { app.followAnimal(a.uid); }
  text("Tile: %s", a.tile);
  text("Hunger: %.0f", a.hunger * 100.0f);
  igSameLine(0, 5);
  if(igButton(cstr("Make hungry##anm_hunger"), ImVec2(0, 0))) { a.hunger = 0.8f; }
  text("Thirst: %.0f", a.thirst * 100.0f);
  igSameLine(0, 5);
  if(igButton(cstr("Make thirsty##anm_thirst"), ImVec2(0, 0))) { a.thirst = 0.8f; }
  text("Job: %s", a.hasJob ? a.currentJob.name : "None");
}

/** Roster of all animals + state summary. */
void showAnimalOverview(ref GameApp app) {
  int idle, walking, working;
  if(app.world.animals !is null) { foreach(i, ref a; app.world.animals.animals) {
    switch(a.state) {
      case EntityState.Idle: idle++; break;
      case EntityState.Moving: case EntityState.Wandering: walking++; break;
      case EntityState.Working: working++; break;
      default: break;
    }
    app.showAnimalRow(i, a);
  } }
  text("Animals: %d | Idle: %d | Moving: %d | Feeding: %d",
       app.world.animals !is null ? app.world.animals.animals.length : 0, idle, walking, working);
}

void showAnimalContent(ref GameApp app, uint font = 0) {
  igSeparator();
  int sel = app.world.animals !is null ? app.world.animals.selected : -1;
  if(sel >= 0 && sel < app.world.animals.animals.length) {
    if(igButton(iconText(cast(string)ICON_FA_ARROW_LEFT, "Back"), ImVec2(0,0))) { app.world.animals.selected = -1; }
    app.showAnimalSheet(app.world.animals.animals[sel], sel);
  } else { app.showAnimalOverview(); }
}
