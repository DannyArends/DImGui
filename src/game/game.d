/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import world : World;
import resources : ResourceAtlas;

struct GameApp {
  App app;
  alias app this;  // GameApp usable everywhere App is expected

  World world;
  ResourceAtlas resourceAtlas;
  bool showPaths = false;
  bool showBounds = false;
  bool showRays = false;
  bool showLights = false;
  bool disco = false;
  bool paused = false;
}
