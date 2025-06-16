/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;
import std.format : format;
import std.conv : to;
import std.traits : EnumMembers;
import std.string : toStringz, fromStringz;

import geometry : aiColorType, Instance, Mesh, TexInfo, Material, Geometry, scale, rotate;
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

TexInfo getTexture(aiMaterial* material, aiTextureType type = aiTextureType_DIFFUSE) {
  aiString texture_path;
  uint uvChannel;
  aiGetMaterialTexture(material, type, 0, &texture_path, null, &uvChannel, null, null, null, null);
  return(TexInfo(to!string(fromStringz(texture_path.data)), uvChannel));
}

float[4] getMaterialColor(aiMaterial* material, aiColorType type = aiColorType.DIFFUSE ) {
  aiColor4D color;
  aiGetMaterialColor(material, type, 0, 0, &color);
  return([color.r,color.g,color.b,color.a]);
}

Material create(aiMaterial* material, const(char)* path, uint id){
  aiString name;
  aiGetMaterialString(material, "?mat.name", 0, 0, &name);
  aiString base;
  aiGetMaterialString(material, "$tex.file", 0, 0, &base);
  Material mat = {
    id : id, 
    path : to!string(fromStringz(path)), 
    name : to!string(fromStringz(name.data)), 
    base : to!string(fromStringz(base.data)) 
  };
  return(mat);
}

OpenAsset loadOpenAsset(ref App app, const(char)* path =  "data/objects/cottage_fbx.fbx", uint channel = 0) {
  version (Android){ }else{ path = toStringz(format("app/src/main/assets/%s", fromStringz(path))); }
  SDL_Log("Loading: %s", path);
  OpenAsset object = new OpenAsset(); 
  auto scene = aiImportFile(path, aiProcess_Triangulate | aiProcess_FlipUVs);
  if (!scene || scene.mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene.mRootNode) {
    SDL_Log("Error loading model '%s': %s", path, aiGetErrorString());
    return object;
  }
  SDL_Log("Model '%s' loaded successfully.", path);

  SDL_Log("%u materials in open asset", scene.mNumMaterials);
  for(uint i = 0; i < scene.mNumMaterials; i++) {
    aiMaterial* material = scene.mMaterials[i];
    Material mat = material.create(path, i);
    foreach(type; EnumMembers!aiTextureType) {
      TexInfo value = material.getTexture(type);
      if(value.path != "") mat.textures[type] = value;
    }
    foreach(type; EnumMembers!aiColorType) {
      mat.colors[type] = material.getMaterialColor(type);
    }
    object.materials ~= mat;
  }
  foreach(material; object.materials) {
    SDL_Log(toStringz(format("  Mat: %s", material)));
  }

  SDL_Log("%u meshes in open asset", scene.mNumMeshes);
  uint vert = 0;
  for(uint i = 0; i < scene.mNumMeshes; i++) {
    auto mesh = scene.mMeshes[i];
    SDL_Log("--- Processing Mesh %d (%s) ---", i, toStringz(mesh.mName.data));
    SDL_Log("  Number of vertices in this mesh: %u\n", mesh.mNumVertices);
    SDL_Log("  Number of faces in this mesh: %u\n", mesh.mNumFaces);
    SDL_Log("  Normals: %p, Color: %p, TexCoord: %p\n", mesh.mNormals, mesh.mColors[0], mesh.mTextureCoords[0]);
    SDL_Log("  Material Index: %u", mesh.mMaterialIndex);

    for (size_t v = 0; v < mesh.mNumVertices; v++) { 
      object.vertices ~= Vertex([mesh.mVertices[v].x, mesh.mVertices[v].y, mesh.mVertices[v].z]);
      if (mesh.mNormals) {
        object.vertices[v].normal = [mesh.mNormals[v].x, mesh.mNormals[v].y,mesh.mNormals[v].z];
      }
      if (mesh.mTextureCoords[channel]) {
        object.vertices[v].texCoord = [mesh.mTextureCoords[channel][v].x, mesh.mTextureCoords[channel][v].y];
      }
      if (mesh.mColors[0]) {
        object.vertices[v].color = [mesh.mColors[0][v].r, mesh.mColors[0][v].g, mesh.mColors[0][v].b, mesh.mColors[0][v].a];
      }
    }
    for (size_t f = 0; f < mesh.mNumFaces; f++) {
      auto face = &mesh.mFaces[f];
      for (size_t j = 0; j < face.mNumIndices; j++) {
        object.indices ~= (vert + face.mIndices[j]);
      }
    }
    object.meshes ~= Mesh([vert, vert + mesh.mNumVertices], mesh.mMaterialIndex);
    vert += mesh.mNumVertices;
    break;
  }
  object.rotate([180.0f, 0.0f, 90.0f]);
  aiReleaseImport(scene);
  return object;
}

