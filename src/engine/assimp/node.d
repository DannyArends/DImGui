/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : Matrix, transpose;
import assimp : OpenAsset, name, toMatrix;
import bone : Bone;
import mesh : loadMesh;

struct Node {
  string name;
  uint lvl = 0;
  Matrix transform;
  Node[] children;
}

Node loadNode(ref App app, ref OpenAsset asset, aiNode* node, aiScene* scene, ref Bone[string] bones, uint lvl = 0) {
  Node n = Node(node.name(), lvl, toMatrix(node.mTransformation));
  //SDL_Log(toStringz(format("%s.nodeTransform: %s", n.name, n.transform)));

  for (uint i = 0; i < node.mNumMeshes; i++){
    aiMesh* mesh = scene.mMeshes[node.mMeshes[i]];
    if(mesh.name() == "Cube") continue;
    app.loadMesh(mesh, asset, bones);
  }

  n.children.length = node.mNumChildren;
  for (uint i = 0; i < node.mNumChildren; ++i) {
    n.children[i] = app.loadNode(asset, node.mChildren[i], scene, bones, lvl+1);
  }
  return(n);
}

