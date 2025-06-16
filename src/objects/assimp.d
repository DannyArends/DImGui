/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;
import std.format : format;
import std.conv : to;
import std.string : toStringz, fromStringz;

import geometry : Instance, Geometry, scale, rotate;
import vertex : Vertex;
import vector : x, y, z;

/** OpenAsset using assimp
 */
class OpenAsset : Geometry {
  this() {
    instances = [Instance()];
    name = (){ return(typeof(this).stringof); };
  }
}

OpenAsset fromMesh(ref App app, aiMesh* mesh, uint mID) {
  OpenAsset object = new OpenAsset();
  SDL_Log("--- Processing Mesh %d (%s) ---", mID, toStringz(mesh.mName.data));
  SDL_Log("  Number of vertices in this mesh: %u\n", mesh.mNumVertices);
  SDL_Log("  Number of faces in this mesh: %u\n", mesh.mNumFaces);
  SDL_Log("  Normals: %p, Color: %p, TexCoord: %p\n", mesh.mNormals, mesh.mColors[0], mesh.mTextureCoords[0]);
  for (size_t v = 0; v < mesh.mNumVertices; v++) { 
    object.vertices ~= Vertex([mesh.mVertices[v].x, mesh.mVertices[v].y, mesh.mVertices[v].z]);
    if (mesh.mNormals) {
      object.vertices[v].normal = [mesh.mNormals[v].x, mesh.mNormals[v].y,mesh.mNormals[v].z];
    }
    if (mesh.mTextureCoords[0]) {
      object.vertices[v].texCoord = [mesh.mTextureCoords[0][v].x, 1.0f - mesh.mTextureCoords[0][v].y];
    }
    if (mesh.mColors[0]) {
      object.vertices[v].color = [mesh.mColors[0][v].r, mesh.mColors[0][v].g, mesh.mColors[0][v].b, mesh.mColors[0][v].a];
    }
  }
  for (size_t f = 0; f < mesh.mNumFaces; f++) {
    auto face = &mesh.mFaces[f];
    for (size_t j = 0; j < face.mNumIndices; j++) {
      object.indices ~= face.mIndices[j];
    }
  }
  object.rotate([180.0f, 0.0f, 90.0f]);
  return(object);
}

OpenAsset[] loadOpenAsset(ref App app, const(char)* path =  "data/objects/cottage_fbx.fbx", int mID = 0) {
  version (Android){ }else{ path = toStringz(format("app/src/main/assets/%s", fromStringz(path))); }
  SDL_Log("Loading: %s", path);
  OpenAsset[] objects = []; 
  auto scene = aiImportFile(path, aiProcess_Triangulate | aiProcess_JoinIdenticalVertices);
  if (!scene || scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene.mRootNode) {
    SDL_Log("Error loading model '%s': %s", path, aiGetErrorString());
    return objects;
  }
  SDL_Log("Model '%s' loaded successfully.", path);
  SDL_Log("Number of meshes in scene: %u", scene.mNumMeshes);
  if(mID >= 0) return([app.fromMesh(scene.mMeshes[mID], mID)]);

  for(uint i = 0; i < scene.mNumMeshes; i++) {
    OpenAsset object = app.fromMesh(scene.mMeshes[i], i);
    objects ~= object;
  }
  aiReleaseImport(scene);
  return objects;
}
