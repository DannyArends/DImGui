/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : Matrix, transpose;

struct Node {
  string name;
  Matrix offset;
  Node[] children;
}

Node loadNode(aiNode* node, uint lvl = 0) {
  Node n = Node();
  n.name = to!string(fromStringz(node.mName.data));
  n.offset = cast(float[16])node.mTransformation;
  n.children.length = node.mNumChildren;
  for (uint i = 0; i < node.mNumChildren; ++i) {
    n.children[i] = loadNode(node.mChildren[i], lvl+1);
  }
  return(n);
}

