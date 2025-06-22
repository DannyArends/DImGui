/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
 
import engine;
import std.algorithm : map, sort;
import std.array : array;
import std.path : stripExtension;

import std.traits : EnumMembers;
import std.string : toStringz, lastIndexOf, fromStringz;

import animation : loadAnimations;
import bone : Bone, loadBones;
import matrix : Matrix, inverse, transpose;
import node : Node, loadNode;
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

Matrix toMatrix(aiMatrix4x4 m){
  float[16] myMatrixArray = [
    m.a1, m.b1, m.c1, m.d1,
    m.a2, m.b2, m.c2, m.d2,
    m.a3, m.b3, m.c3, m.d3,
    m.a4, m.b4, m.c4, m.d4
  ];
  return(Matrix(myMatrixArray));
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

string name(T)(T* obj){ 
  size_t idx = 0;
  do {
    ++idx;
  } while (obj.mName.data[idx] != '\0');
  return(to!string(toStringz(obj.mName.data[0 .. idx] ~ '\0'))); 
}

void loadMesh(ref App app, aiMesh* mesh, ref OpenAsset asset, ref Bone[string] globalBones) {
  //if (app.verbose) {
    SDL_Log("--- Processing Mesh (%s) ---", toStringz(mesh.mName.data));
    SDL_Log("  Number of vertices in this mesh: %u\n", mesh.mNumVertices);
    SDL_Log("  Number of faces in this mesh: %u\n", mesh.mNumFaces);
    SDL_Log("  Normals: %p, Color: %p, TexCoord: %p\n", mesh.mNormals, mesh.mColors[0], mesh.mTextureCoords[0]);
    SDL_Log("  Material Index: %u / %u", mesh.mMaterialIndex, asset.materials.length);
    SDL_Log("  %u Bones", mesh.mNumBones); // New: Log bone count
  //}
  uint vertOff = cast(uint)(asset.vertices.length);
  auto texInfo = app.matchTexture(asset, mesh.mMaterialIndex, aiTextureType_DIFFUSE);
  auto weights = mesh.loadBones(globalBones);
  for (size_t vIdx = 0; vIdx < mesh.mNumVertices; vIdx++) {
    size_t gIdx = vIdx + vertOff;
    asset.vertices ~= Vertex([mesh.mVertices[vIdx].x, mesh.mVertices[vIdx].y, mesh.mVertices[vIdx].z]);
    if (mesh.mNormals) {
      asset.vertices[gIdx].normal = [mesh.mNormals[vIdx].x, mesh.mNormals[vIdx].y,mesh.mNormals[vIdx].z];
    }
    if (mesh.mTextureCoords[texInfo.channel]) {
      asset.vertices[gIdx].texCoord = [mesh.mTextureCoords[texInfo.channel][vIdx].x, mesh.mTextureCoords[texInfo.channel][vIdx].y];
    }
    if (mesh.mColors[0]) {
      asset.vertices[gIdx].color = [mesh.mColors[0][vIdx].r, mesh.mColors[0][vIdx].g, mesh.mColors[0][vIdx].b, mesh.mColors[0][vIdx].a];
    }
    asset.vertices[gIdx].tid = texInfo.tid;
    float[string] distances;
    foreach(name; weights.keys){
      auto p = globalBones[name].bindPosition;
      distances[name] = euclidean(asset.vertices[gIdx].position, p);
    }
    auto sorted = distances.byKeyValue.array.sort!((a, b) => a.value < b.value);
    uint n = 0;
    foreach (s; sorted) {
      if (n >= 4) break;
      if (cast(uint)vIdx in weights[s.key]) { // Make sure the clostest bone is affecting the vertex
        asset.vertices[gIdx].bones[n] = globalBones[s.key].index;
        asset.vertices[gIdx].weights[n] = weights[s.key][cast(uint)vIdx];
        n++;
      }
    }
  }
  for (size_t f = 0; f < mesh.mNumFaces; f++) {
    auto face = &mesh.mFaces[f];
    for (size_t j = 0; j < face.mNumIndices; j++) {
      asset.indices ~= (vertOff + face.mIndices[j]);
    }
  }
  asset.meshes[mesh.name()] = Mesh([vertOff, vertOff + mesh.mNumVertices], mesh.mMaterialIndex);
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

  object.materials = app.loadMaterials(path, scene);
  Bone[string] bones;
  app.rootnode = app.loadNode(object, scene.mRootNode, scene, bones);

  object.bones = bones;
  app.animations = app.loadAnimations(scene);
  aiReleaseImport(scene);
  return object;
}

