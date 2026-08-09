/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

immutable(Reaction) reactionFor(string name) {
  foreach(ref r; reactionTable) { if(r.name == name) { return r; } }
  return Reaction.init;
}
