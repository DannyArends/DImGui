/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import camera : move;
import imgui : faIcon;

/** Show on-screen movement joystick buttons centered at bottom of screen, Android only
 */
void showJoystickwindow(ref App app, uint font = 0) {
  version(Android) {
    igPushFont(app.gui.fonts[font], app.gui.fontsize(1.5f));

    float bs  = 55.0f * app.gui.uiscale;
    float pad = 8.0f * app.gui.uiscale;
    float winW = bs * 3.0f + pad * 4.0f;
    float winH = bs * 3.0f + pad * 4.0f;
    float x = (app.camera.width  - winW) * 0.5f;
    float y =  app.camera.height - winH - pad;

    igSetNextWindowPos(ImVec2(x, y), 0, ImVec2(0.0f, 0.0f));
    igSetNextWindowSize(ImVec2(winW, winH), 0);
    auto flags = ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar |
                 ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoScrollbar |
                 ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;

    igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, bs * 0.5f);

    igBegin("Joystick", null, flags);
    ImVec2 bsize = ImVec2(bs, bs);

    igSetCursorPos(ImVec2(bs + pad * 2.0f, pad));
    igButton(faIcon(cast(string)ICON_FA_ARROW_UP),    bsize);
    if(igIsItemActive()) app.camera.move(app.camera.forward());

    igSetCursorPos(ImVec2(pad, bs + pad * 2.0f));
    igButton(faIcon(cast(string)ICON_FA_ARROW_LEFT),  bsize);
    if(igIsItemActive()) app.camera.move(app.camera.left());

    igSetCursorPos(ImVec2(bs * 2.0f + pad * 3.0f, bs + pad * 2.0f));
    igButton(faIcon(cast(string)ICON_FA_ARROW_RIGHT), bsize);
    if(igIsItemActive()) app.camera.move(app.camera.right());

    igSetCursorPos(ImVec2(bs + pad * 2.0f, bs * 2.0f + pad * 3.0f));
    igButton(faIcon(cast(string)ICON_FA_ARROW_DOWN),  bsize);
    if(igIsItemActive()) app.camera.move(app.camera.back());

    igEnd();
    igPopStyleVar(1);
    igPopFont();
  }
}
