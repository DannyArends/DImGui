/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;
import std.algorithm : map, sort;
import std.array : array;
import std.path : stripExtension;
import std.format : format;
import std.conv : to;

import std.traits : EnumMembers;
import std.string : toStringz, lastIndexOf, fromStringz;

import animation : loadNode, loadAnimations;
import bone : Bone, loadBones;
import matrix : Matrix, inverse;
import geometry : aiColorType, Instance, Mesh, TexInfo, Material, Geometry, scale, rotate;
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

TexInfo getTexture(aiMaterial* material, aiTextureType type = aiTextureType_DIFFUSE) {
  aiString texture_path;
  uint uvChannel;
  aiGetMaterialTexture(material, type, 0, &texture_path, null, &uvChannel, null, null, null, null);
  return(TexInfo(to!string(fromStringz(texture_path.data)), -1, uvChannel));
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

TexInfo matchTexture(ref App app, ref OpenAsset object, uint materialIndex, aiTextureType type = aiTextureType_DIFFUSE) {
  TexInfo texInfo = {object.materials[materialIndex].name};
  if (type in object.materials[materialIndex].textures) {
    texInfo = object.materials[materialIndex].textures[type];
  }
  auto idx = texInfo.path.lastIndexOf("\\");
  if(idx >= 0) texInfo.path = stripExtension(texInfo.path[(idx+1)..($)]);
  texInfo.tid = app.textures.idx(toStringz(texInfo.path));
  SDL_Log(toStringz(format("  Material: %s -> %d at channel: %d", texInfo.path, texInfo.tid, texInfo.channel)));
  return(texInfo);
}

Material[] loadMaterials(ref App app, const(char)* path, aiScene* scene){
  Material[] materials;
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
    materials ~= mat;
  }
  return(materials);
}

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

  app.rootnode = loadNode(scene.mRootNode);

  object.materials = app.loadMaterials(path, scene);

  Bone[string] bones;
  uint vert = 0;
  for(uint i = 0; i < scene.mNumMeshes; i++) {
    auto mesh = scene.mMeshes[i];
    if(to!string(toStringz(mesh.mName.data)) == "Cube") continue; // Do not load in cubes or other nonsense
    if (app.verbose) {
      SDL_Log("--- Processing Mesh %d (%s) ---", i, toStringz(mesh.mName.data));
      SDL_Log("  Number of vertices in this mesh: %u\n", mesh.mNumVertices);
      SDL_Log("  Number of faces in this mesh: %u\n", mesh.mNumFaces);
      SDL_Log("  Normals: %p, Color: %p, TexCoord: %p\n", mesh.mNormals, mesh.mColors[0], mesh.mTextureCoords[0]);
      SDL_Log("  Material Index: %u / %u", mesh.mMaterialIndex, object.materials.length);
      SDL_Log("  %u Bones", mesh.mNumBones); // New: Log bone count
    }
    auto texInfo = app.matchTexture(object, mesh.mMaterialIndex, aiTextureType_DIFFUSE);
    mesh.loadBones(bones);

    for (size_t vIdx = 0; vIdx < mesh.mNumVertices; vIdx++) {
      size_t gIdx = vIdx + vert;
      object.vertices ~= Vertex([mesh.mVertices[vIdx].x, mesh.mVertices[vIdx].y, mesh.mVertices[vIdx].z]);
      if (mesh.mNormals) {
        object.vertices[gIdx].normal = [mesh.mNormals[vIdx].x, mesh.mNormals[vIdx].y,mesh.mNormals[vIdx].z];
      }
      if (mesh.mTextureCoords[texInfo.channel]) {
        object.vertices[gIdx].texCoord = [mesh.mTextureCoords[texInfo.channel][vIdx].x, mesh.mTextureCoords[texInfo.channel][vIdx].y];
      }
      if (mesh.mColors[0]) {
        object.vertices[gIdx].color = [mesh.mColors[0][vIdx].r, mesh.mColors[0][vIdx].g, mesh.mColors[0][vIdx].b, mesh.mColors[0][vIdx].a];
      }
      object.vertices[gIdx].tid = texInfo.tid;
      float[string] distances;
      foreach(name, bone; bones){
        auto p = bone.bindPosition;
        distances[name] = euclidean(object.vertices[gIdx].position, p);
      }
      auto sorted = distances.byKeyValue.array.sort!((a, b) => a.value < b.value);
      uint n = 0;
      foreach (s; sorted) {
        if (n >= 4) break;
        if (cast(uint)vIdx in bones[s.key].weights) { // Make sure the clostest bone is affecting the vertex
          object.vertices[gIdx].bones[n] = bones[s.key].index;
          object.vertices[gIdx].weights[n] = bones[s.key].weights[cast(uint)vIdx];
          n++;
        }
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
  }
  app.animations = app.loadAnimations(scene);
  object.bones = bones;
  object.rotate([180.0f, 0.0f, 90.0f]);
  aiReleaseImport(scene);
  return object;
}

