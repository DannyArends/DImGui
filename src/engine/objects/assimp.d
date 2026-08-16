/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;

import animation : loadAnimations;
import bone : mergeBones;
import boundingbox : computeBoundingBox, calculateBounds, computeScaleAdjustment;
import matrix : toMatrix, multiply, inverse, transpose, rotate;
import node : loadNode;
import mesh : updateMeshInfo;
import meta : loadMetaData;
import io : readFile;
import amat : loadMaterials;
import textures : idx;
import turtlegfx : buildClips, rigToNode, rigBones;
import matrix : translate;
import normals : computeNormals, computeTangents;
import vector : x, y, z, euclidean;

/** OpenAsset using assimp
 */
class OpenAsset : Geometry {
  Bone[string] bones;   /// Local bone map, merged into app.bones on main thread
  this() {
    instances = [DrawInstance()];
    isOpaque = false;
    mName = typeof(this).stringof;
  }

  /** Load an assimp asset directly into this instance (subclasses call super(path)). */
  this(const(char)* path, bool verbose = false, bool isVisible = false) {
    this();
    loadInto(this, path, verbose, isVisible);
  }
}

bool isOpenAsset(string path) {
  if(extension(path) == ".obj") return(true);
  if(extension(path) == ".fbx") return(true);
  return(false);
}

/** Assemble a vertexless skinned asset from a rig + clips: node tree, bones, animations, palette region,
 *  and the per-node local bone slot table. Registers it in app.objects and stamps its region immediately. */
OpenAsset buildSkinnedAsset(ref App app, const RigNode[] rig, immutable AnimClip[] clips, string prefix, string name, uint seed, out int[] slot) {
  auto s = new OpenAsset();
  s.mName = name;
  s.instancedMesh = true; s.instances = [DrawInstance()]; s.states.length = 1;
  s.rootnode = rigToNode(rig, prefix);
  s.bones = rigBones(rig, prefix);
  s.animations = buildClips(rig, prefix, clips, seed);
  app.mergeBones(s);
  slot.length = rig.length;
  foreach(k; 0 .. rig.length){
    slot[k] = cast(int)(app.bones[format("%s%d", prefix, k)].index - s.boneBase);
  }
  return s;
}

/** Load an assimp asset into an existing OpenAsset instance */
void loadInto(OpenAsset object, const(char)* path, bool verbose = false, bool isVisible = false) {
  SDL_Log("Loading: %s", path);

  auto content = readFile(path);
  auto flags = aiProcess_Triangulate | aiProcess_ConvertToLeftHanded | aiProcessPreset_TargetRealtime_MaxQuality ;
  auto scene = aiImportFileFromMemory(&content[0], cast(uint)content.length, flags, toStringz(extension(to!string(path))));

  if (!scene || scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene.mRootNode) {
    SDL_Log("Error loading model '%s': %s", path, aiGetErrorString());
    return;
  }

  object.mName = stripExtension(baseName(to!string(path)));
  object.mData = loadMetaData(scene, verbose);

  object.box = new BoundingBox();
  object.box.bounds.calculateBounds(scene, scene.mRootNode, Matrix());

  object.materials = loadMaterials(scene, path);
  object.animations = loadAnimations(scene, object, verbose);
  object.rootnode = loadNode(object, scene, scene.mRootNode, Matrix(), verbose);

  if (object.mName == "Spider") { // The Spider model is broken, it floats above
    object.rootnode.transform = object.rootnode.transform.translate([0.0f, -775.0f, 0.0f]);
    isVisible = true;
  }

  object.instances[0] = object.box.bounds.computeScaleAdjustment(); // Adjust the scale to 4.0f

  if (verbose) {
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
}

/** Load an OpenAsset */
OpenAsset loadOpenAsset(const(char)* path, bool verbose = false, bool isVisible = false) {
  OpenAsset object = new OpenAsset();
  loadInto(object, path, verbose, isVisible);
  return object;
}

/** Get the name from a char[256] */
string name(T)(T obj) {
  size_t idx = 0;
  do { ++idx; } while (obj.data[idx] != '\0');
  return(to!string(toStringz(obj.data[0 .. idx] ~ '\0'))); 
}

/** Construct a unique name for a node within an OpenAsset */
string nodeName(const OpenAsset asset, const string node){ return(format("%s:%d:%s", asset.mName, asset.uid, node)); }
