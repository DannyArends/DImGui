/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import imgui : faIcon;
import widgets : text;

/** Coloured FontAwesome glyph tinted by the entity's colour. */
void entityGlyph(T)(ref T e, string icon) {
  igPushStyleColor_Vec4(ImGuiCol_Text, ImVec4(e.color[0], e.color[1], e.color[2], e.color[3]));
  text("%s", fromStringz(faIcon(icon)));
  igPopStyleColor(1);
}

/** Camera follow: track the uid-matching entity each frame until it's gone. */
void followEntity(M)(ref GameApp app, uint uid, M manager) {
  app.camera.onFrame = (dt) {
    foreach(ref e; manager){ if(e.uid == uid) { app.camera.lookat = e.visualPos; app.camera.isDirty = true; return; } }
    app.camera.onFrame = null;
  };
}

/** Need readout with a debug "set high" button. */
void needToggle(string label, string verb, ref float need, string id) {
  text("%s: %.0f", label, need * 100.0f);
  igSameLine(0, 5);
  if(igButton(cstr("Make %s##%s", verb, id), ImVec2(0, 0))) { need = 0.8f; }
}
