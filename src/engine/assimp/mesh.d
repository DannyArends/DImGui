/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : OpenAsset, name;
import bone : Bone, BoneWeights, loadBones;
import material : matchTexture;
import matrix : Matrix, multiply, inverse, transpose;
import vector : euclidean,x,y,z;
import vertex : Vertex;

struct Mesh {
  uint[2] vertices;       /// Start .. End positions in Geometry.vertices array
  uint material;          /// Mesh material index
}

string loadMesh(ref App app, aiMesh* mesh, ref OpenAsset asset, const Matrix gTransform) {
  if (app.verbose) {
    SDL_Log("Mesh: %s", toStringz(name(mesh.mName)));
    SDL_Log(" - %u vertices, %u faces, %u bones", mesh.mNumVertices, mesh.mNumFaces, mesh.mNumBones);
    SDL_Log(" - %u / %u material", mesh.mMaterialIndex, asset.materials.length);
  }
  Mesh mMesh = Mesh([cast(uint)(asset.vertices.length), cast(uint)(asset.vertices.length) + mesh.mNumVertices], mesh.mMaterialIndex);

  // Vertex offset, load texture information,  bone weight, and normal matrix
  size_t vOff = asset.vertices.length;
  auto texInfo = app.matchTexture(asset, mesh.mMaterialIndex, aiTextureType_DIFFUSE);
  auto weights = asset.loadBones(mesh, app.bones, gTransform);
  auto normMatrix = gTransform.inverse().transpose();

  for (size_t vIdx = 0; vIdx < mesh.mNumVertices; vIdx++) {  // Load vertex information
    size_t gIdx = (vOff + vIdx);
    asset.vertices ~= Vertex(gTransform.multiply([mesh.mVertices[vIdx].x, mesh.mVertices[vIdx].y, mesh.mVertices[vIdx].z]));

    if (mesh.mNormals) {
      asset.vertices[gIdx].normal = normMatrix.multiply([mesh.mNormals[vIdx].x, mesh.mNormals[vIdx].y,mesh.mNormals[vIdx].z]);
    }
    if (mesh.mTextureCoords[texInfo.channel]) {
      asset.vertices[gIdx].texCoord = [mesh.mTextureCoords[texInfo.channel][vIdx].x, mesh.mTextureCoords[texInfo.channel][vIdx].y];
    }
    if (mesh.mColors[texInfo.channel]) {
      auto color = mesh.mColors[texInfo.channel][vIdx];
      asset.vertices[gIdx].color = [color.r, color.g, color.b, color.a];
    }
    asset.vertices[gIdx].tid = texInfo.tid;
    asset.assignBoneWeight(gIdx, weights, vIdx, app.bones);
  }

  for (size_t f = 0; f < mesh.mNumFaces; f++) {  // Load faces to indices
    auto face = &mesh.mFaces[f];
    for (size_t j = 0; j < face.mNumIndices; j++) {
      asset.indices ~= cast(uint)(vOff + face.mIndices[j]);
    }
  }
  asset.meshes[name(mesh.mName)] = mMesh;
  return(name(mesh.mName));
}

void assignBoneWeight(ref OpenAsset asset, size_t gIdx, BoneWeights weights, size_t vIdx, ref Bone[string] globalBones) {
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

