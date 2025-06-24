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
import io : readFile;
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

struct MetaData {
  int[4] upAxis;
  int[2] frontAxis;
  int[2] coordAxis;
  double scalefactor;
}

/** Load an OpenAsset 
 */
OpenAsset loadOpenAsset(ref App app, const(char)* path) {
  SDL_Log("Loading: %s", path);
  OpenAsset object = new OpenAsset();

  auto content = readFile(path);
  auto flags = aiProcess_Triangulate | aiProcess_FlipUVs | aiProcess_ConvertToLeftHanded | aiProcess_GenBoundingBoxes;
  auto scene = aiImportFileFromMemory(&content[0], cast(uint)content.length, flags, toStringz(extension(to!string(path))));

  if (!scene || scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene.mRootNode) {
    SDL_Log("Error loading model '%s': %s", path, aiGetErrorString());
    return object;
  }

  aiMetadata* mData = scene.mMetaData;
  for (uint i = 0; i < mData.mNumProperties; ++i) {
    auto key = name(mData.mKeys[i]);
    if (key == "UpAxis") { object.mData.upAxis[0] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "UpAxisSign") { object.mData.upAxis[1] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "OriginalUpAxis") { object.mData.upAxis[2] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "OriginalUpAxisSign") { object.mData.upAxis[3] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "FrontAxis") { object.mData.frontAxis[0] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "FrontAxisSign") { object.mData.frontAxis[1] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "CoordAxis") { object.mData.coordAxis[0] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "CoordAxisSign") { object.mData.coordAxis[1] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "UnitScaleFactor") { object.mData.scalefactor = *cast(float*)(mData.mValues[i].mData); }
  }
  SDL_Log(toStringz(format("UP: %s", object.mData.upAxis)));
  SDL_Log(toStringz(format("Front: %s", object.mData.frontAxis)));
  SDL_Log(toStringz(format("Coord: %s", object.mData.coordAxis)));
  SDL_Log(toStringz(format("Scale: %s", object.mData.scalefactor)));

  object.mName = stripExtension(baseName(to!string(path)));

  SDL_Log("Model '%s' loaded successfully.", toStringz(object.mName));
  SDL_Log("%u meshes, %u materials, %u animations", scene.mNumMeshes, scene.mNumMaterials, scene.mNumAnimations);
  object.materials = app.loadMaterials(path, scene);
  object.rootnode = app.loadNode(object, scene.mRootNode, scene, app.bones);
  object.animations = app.loadAnimations(object, scene);
  SDL_Log("%u vertices, %u indices loaded", object.vertices.length, object.indices.length);
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
string name(T)(T obj) {
  size_t idx = 0;
  do { ++idx; } while (obj.data[idx] != '\0');
  return(to!string(toStringz(obj.data[0 .. idx] ~ '\0'))); 
}
