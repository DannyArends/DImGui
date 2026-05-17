/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

struct Material {
  int tid = -1;
  int nid = -1;
  int oid = -1;
  int pad = -1;
}

struct MaterialList {
  Material[] materials;
  ulong capacity = 256;
  alias materials this;
}