/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : OpenAsset;
import textures : idx;

enum aiColorType : const(char)* { DIFFUSE = "$clr.diffuse", AMBIENT = "$clr.ambient",  SPECULAR = "$clr.specular" };

struct TexureInfo {
  string path;
  uint channel;
  alias path this;
}

struct Material {
  string path;
  TexureInfo[aiTextureType] textures;
  float[4][aiColorType] colors;
}

TexureInfo getTextureInfo(aiMaterial* material, aiTextureType type = aiTextureType_DIFFUSE) {
  aiString path;
  uint uvChannel;
  aiGetMaterialTexture(material, type, 0, &path, null, &uvChannel, null, null, null, null);
  string p = to!string(fromStringz(path.data));
  auto idx = p.lastIndexOf("\\");
  if(idx >= 0) p = stripExtension(p[(idx+1)..($)]);
  return(TexureInfo(p, uvChannel));
}

float[4] getMaterialColor(aiMaterial* material, aiColorType type = aiColorType.DIFFUSE ) {
  aiColor4D color;
  aiGetMaterialColor(material, type, 0, 0, &color);
  return([color.r, color.g, color.b, color.a]);
}

int getTexture(T)(ref App app, T object, uint materialIndex, aiTextureType type = aiTextureType_DIFFUSE){
  if (type in object.materials[materialIndex].textures) {
    int index = idx(app.textures, object.materials[materialIndex].textures[type]);
    return(index);
  }
  return(-1);
}

int getChannel(T)(ref App app, T object, uint materialIndex, aiTextureType type = aiTextureType_DIFFUSE) {
  if (type in object.materials[materialIndex].textures) {
    return(object.materials[materialIndex].textures[type].channel);
  }
  return(0);
}

Material[] loadMaterials(ref App app, aiScene* scene, const(char)* path){
  Material[] materials;
  for(uint i = 0; i < scene.mNumMaterials; i++) {
    aiMaterial* material = scene.mMaterials[i];
    Material mat =  { path : to!string(fromStringz(path)) };
    foreach(type; EnumMembers!aiTextureType) {
      auto info = material.getTextureInfo(type);
      if(info.path != ""){ mat.textures[type] = info; }
    }
    foreach(type; EnumMembers!aiColorType) {
      mat.colors[type] = material.getMaterialColor(type);
    }
    materials ~= mat;
  }
  return(materials);
}
