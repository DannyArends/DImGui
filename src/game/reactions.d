/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

/** Whether a reaction needs a workshop: None (on-the-knee), Required, or Preferred (either; bonus is v0.2). */
enum WorkshopUse : ubyte { None, Required, Preferred }

/** One input line of a reaction: a resource type and a count. */
struct Ingredient { ubyte cls; uint count = 1; }

/** One input line of a reaction: a resource type and a count. */
struct Product { ubyte type; float chance = 1.0f; uint count = 1; }

struct Reaction {
  string name, verb, skill;
  WorkshopUse workshop;
  Ingredient[] inputs;
  Product[] outputs;
}

immutable(Reaction) reactionFor(string name) {
  foreach(ref r; reactionTable) { if(r.name == name) { return r; } }
  return Reaction.init;
}
