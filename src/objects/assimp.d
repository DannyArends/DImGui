/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import animation : loadAnimations;
import bone : Bone, loadBones;
import matrix : Matrix, inverse, transpose;
import node : Node, loadNode;
import mesh : Mesh;
import material : loadMaterials;
import geometry : Instance, Geometry, scale, rotate;
import vertex : Vertex;
import textures : idx;
import vector : x, y, z, euclidean;

/** OpenAsset using assimp
 */
class OpenAsset : Geometry {
  this() {
    instances = [Instance()];
    name = (){ return(typeof(this).stringof); };
  }
}

/** Load an OpenAsset 
 */
OpenAsset loadOpenAsset(ref App app, const(char)* path) {
  version (Android){ }else{ path = toStringz(format("app/src/main/assets/%s", fromStringz(path))); }
  SDL_Log("Loading: %s", path);
  OpenAsset object = new OpenAsset(); 
  auto scene = aiImportFile(path, aiProcess_Triangulate | aiProcess_FlipUVs);
  if (!scene || scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene.mRootNode) {
    SDL_Log("Error loading model '%s': %s", path, aiGetErrorString());
    return object;
  }
  SDL_Log("Model '%s' loaded successfully.", path);
  SDL_Log("%u meshes in open asset", scene.mNumMeshes);
  SDL_Log("%u materials in open asset", scene.mNumMaterials);
  SDL_Log("%u animations in open asset", scene.mNumAnimations);

  object.materials = app.loadMaterials(path, scene);
  Bone[string] bones;
  app.rootnode = app.loadNode(object, scene.mRootNode, scene, bones);

  object.bones = bones;
  app.animations = app.loadAnimations(scene);
  if(app.animations.length == 0) object.rotate([0.0f, 180.0f, 90.0f]);
  aiReleaseImport(scene);
  return object;
}

/** Convert from row-based aiMatrix to our column-based Matrix type
 */
Matrix toMatrix(aiMatrix4x4 m){
  float[16] myMatrixArray = [
    m.a1, m.b1, m.c1, m.d1,
    m.a2, m.b2, m.c2, m.d2,
    m.a3, m.b3, m.c3, m.d3,
    m.a4, m.b4, m.c4, m.d4
  ];
  return(Matrix(myMatrixArray));
}

/** Get the name from a char[256]
 */
string name(T)(T* obj) {
  size_t idx = 0;
  do { ++idx; } while (obj.mName.data[idx] != '\0');
  return(to!string(toStringz(obj.mName.data[0 .. idx] ~ '\0'))); 
}
