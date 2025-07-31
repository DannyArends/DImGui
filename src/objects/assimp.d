/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import animation : loadAnimations;
import bone : Bone;
import boundingbox : computeBoundingBox, calculateBounds, computeScaleAdjustment;
import matrix : Matrix, toMatrix, multiply, inverse, transpose, rotate;
import node : Node, loadNode;
import mesh : Mesh;
import meta : loadMetaData;
import io : readFile;
import material : loadMaterials;
import geometry : Instance, Geometry, scale, rotate, computeNormals, computeTangents;
import vertex : Vertex;
import textures : idx;
import matrix : translate;
import vector : x, y, z, euclidean;

/** OpenAsset using assimp
 */
class OpenAsset : Geometry {
  this() {
    instances = [Instance()];
    name = (){ return(this.stringof); };
  }
}

bool isOpenAsset(string path){
  if(extension(path) == ".obj") return(true);
  if(extension(path) == ".fbx") return(true);
  return(false);
}

/** Load an OpenAsset 
 */
OpenAsset loadOpenAsset(ref App app, const(char)* path, bool isVisible = false) {
  SDL_Log("Loading: %s", path);
  OpenAsset object = new OpenAsset();

  auto content = readFile(path);
  auto flags = aiProcess_Triangulate | aiProcess_ConvertToLeftHanded | aiProcessPreset_TargetRealtime_MaxQuality ;
  auto scene = aiImportFileFromMemory(&content[0], cast(uint)content.length, flags, toStringz(extension(to!string(path))));

  if (!scene || scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene.mRootNode) {
    SDL_Log("Error loading model '%s': %s", path, aiGetErrorString());
    return object;
  }

  object.mName = stripExtension(baseName(to!string(path)));
  object.mData = app.loadMetaData(scene);

  object.bounds.calculateBounds(scene, scene.mRootNode, Matrix());

  object.materials = app.loadMaterials(scene, path);
  object.animations = app.loadAnimations(scene, object);
  object.rootnode = app.loadNode(object, scene, scene.mRootNode, Matrix());

  if (object.mName == "Spider") { // The Spider model is broken, it floats above
    object.rootnode.transform = object.rootnode.transform.translate([0.0f, -775.0f, 0.0f]);
    isVisible = true;
  }

  object.instances[0] = object.bounds.computeScaleAdjustment(); // Adjust the scale to 4.0f

  if (app.verbose) {
    SDL_Log("Model '%s' loaded successfully.", toStringz(object.mName));
    SDL_Log("%u meshes, %u materials, %u animations", scene.mNumMeshes, scene.mNumMaterials, scene.mNumAnimations);
    SDL_Log("%u vertices, %u indices loaded", object.vertices.length, object.indices.length);
  }
  aiReleaseImport(scene);
  object.computeNormals();
  object.computeTangents();
  object.computeBoundingBox();
  object.isVisible = isVisible;
  object.scale([0.5f, 0.5f, 0.5f]);
  return object;
}

/** Get the name from a char[256]
 */
string name(T)(T obj) {
  size_t idx = 0;
  do { ++idx; } while (obj.data[idx] != '\0');
  return(to!string(toStringz(obj.data[0 .. idx] ~ '\0'))); 
}

