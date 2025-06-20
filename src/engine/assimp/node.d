/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : Matrix, transpose;
import assimp : name, toMatrix;

struct Node {
  string name;
  uint lvl = 0;
  Matrix transform;
  Node[] children;
}

Node loadNode(aiNode* node, uint lvl = 0) {
  Node n = Node(node.name(), lvl, toMatrix(node.mTransformation));
  n.children.length = node.mNumChildren;
  for (uint i = 0; i < node.mNumChildren; ++i) {
    n.children[i] = loadNode(node.mChildren[i], lvl+1);
  }
  return(n);
}

