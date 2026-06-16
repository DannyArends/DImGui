/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import camera : move;
import imgui : faIcon;

/** Show on-screen movement joystick buttons centered at bottom of screen, Android only */
void showJoystickwindow(ref App app, uint font = 0) {
  version(Android) {
    igPushFont(app.gui.fonts[font], app.gui.fontsize(1.5f));

    float bs  = 45.0f * app.gui.uiscale;
    float pad = 4.0f  * app.gui.uiscale;
    float winW = bs * 3.0f + pad * 4.0f;          // 3 columns (left | mid | right)
    float winH = bs * 3.0f + pad * 4.0f;          // 3 rows
    float x = (app.camera.width  - winW) * 0.5f;
    float y =  app.camera.height - winH - pad;

    igSetNextWindowPos(ImVec2(x, y), 0, ImVec2(0.0f, 0.0f));
    igSetNextWindowSize(ImVec2(winW, winH), 0);
    auto flags = ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoScrollbar |
                 ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoNav;

    igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, bs * 0.5f);
    igBegin("Joystick", null, flags);
    ImVec2 bsize = ImVec2(bs, bs);

    float cMid = bs + pad * 2.0f;            // middle column / row
    float cRight = bs * 2.0f + pad * 3.0f;   // right column
    float cLeft = pad;                       // left column
    float rTop = pad, rMid = cMid, rBot = cRight;

    // Middle column: forward / (centre) / back
    igSetCursorPos(ImVec2(cMid, rTop));
    igButton(faIcon(cast(string)ICON_FA_ARROW_UP), bsize);
    if(igIsItemActive()) app.camera.move(app.camera.forward());

    igSetCursorPos(ImVec2(cMid, rBot));
    igButton(faIcon(cast(string)ICON_FA_ARROW_DOWN), bsize);
    if(igIsItemActive()) app.camera.move(app.camera.back());

    // Sides: left / right
    igSetCursorPos(ImVec2(cLeft, rMid));
    igButton(faIcon(cast(string)ICON_FA_ARROW_LEFT), bsize);
    if(igIsItemActive()) app.camera.move(app.camera.left());

    igSetCursorPos(ImVec2(cRight, rMid));
    igButton(faIcon(cast(string)ICON_FA_ARROW_RIGHT), bsize);
    if(igIsItemActive()) app.camera.move(app.camera.right());

    // Altitude: page up (top-left) / page down (bottom-right corner)
    igSetCursorPos(ImVec2(cLeft, rTop));
    igButton(faIcon(cast(string)ICON_FA_ANGLES_UP), bsize);
    if(igIsItemActive()) app.camera.move(app.camera.pgup());

    igSetCursorPos(ImVec2(cRight, rBot));
    igButton(faIcon(cast(string)ICON_FA_ANGLES_DOWN), bsize);
    if(igIsItemActive()) app.camera.move(app.camera.down());

    igEnd();
    igPopStyleVar(1);
    igPopFont();
  }
}
