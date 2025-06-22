/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : OpenAsset;
import textures : idx;

enum aiColorType : const(char)* { DIFFUSE = "$clr.diffuse", AMBIENT = "$clr.ambient",  SPECULAR = "$clr.specular" };

struct TexInfo {
  string path;
  int tid;
  uint channel;
  alias path this;
}

struct Material {
  uint id;
  string path;
  string name;
  string base;
  TexInfo[aiTextureType] textures;
  float[4][aiColorType] colors;
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
  //SDL_Log(toStringz(format("  Material: %s -> %d at channel: %d", texInfo.path, texInfo.tid, texInfo.channel)));
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
