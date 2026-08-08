/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : faIcon;
import shadow : NUM_CASCADES;
import widgets : text, infoRow;

/** Shadow / CSM diagnostics: per-cascade coverage radius, texel size, map dimension, and slot state. */
void showShadowContent(ref App app, uint font) {
  uint dim = app.shadows.dimension;
  text("Dimension: %d   Active: %d   Static rebuilt: %d", dim, app.shadows.activeShadowMaps, app.shadows.staticRebuilds);
  text("Bounds: height=%.0f  radius=%.0f", app.shadows.bounds[0], app.shadows.bounds[1]);

  foreach(c; 0 .. NUM_CASCADES) {
    float r = app.shadows.cascadeRadius[c];
    float texel = (r > 0.0f) ? (2.0f * r / cast(float)dim) : 0.0f;
    text("C%d  r=%.1f  texel=%.4f  world/px", c, r, texel);
  }
}
