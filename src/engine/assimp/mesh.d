/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : OpenAsset, name;
import bone : Bone, BoneWeights, loadBones;
import bounds : Bounds, update;
import material : matchTexture;
import vector : euclidean,x,y,z;
import vertex : Vertex;

struct Mesh {
  uint[2] vertices;       /// Start .. End positions in Geometry.vertices array
  uint material;          /// Mesh material index
  Bounds bounds;          /// Boudning box for the mesh
}

void LoadVertexBoneWeight(ref OpenAsset asset, size_t gIdx, BoneWeights weights, size_t vIdx, ref Bone[string] globalBones) {
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

string loadMesh(ref App app, aiMesh* mesh, ref OpenAsset asset) {
  SDL_Log("Processing Mesh (%s)", toStringz(name(mesh.mName)));
  if (app.verbose) {
    SDL_Log("  Number of vertices in this mesh: %u\n", mesh.mNumVertices);
    SDL_Log("  Number of faces in this mesh: %u\n", mesh.mNumFaces);
    SDL_Log("  Normals: %p, Color: %p, TexCoord: %p\n", mesh.mNormals, mesh.mColors[0], mesh.mTextureCoords[0]);
    SDL_Log("  Material Index: %u / %u", mesh.mMaterialIndex, asset.materials.length);
    SDL_Log("  %u Bones", mesh.mNumBones); // New: Log bone count
  }
  Mesh mMesh = Mesh([cast(uint)(asset.vertices.length), cast(uint)(asset.vertices.length) + mesh.mNumVertices], mesh.mMaterialIndex);

  // Load texture information and bone weight
  auto texInfo = app.matchTexture(asset, mesh.mMaterialIndex, aiTextureType_DIFFUSE);
  auto weights = asset.loadBones(mesh, app.bones);

  // Load vertices
  for (size_t vIdx = 0; vIdx < mesh.mNumVertices; vIdx++) {
    size_t gIdx = (mMesh.vertices[0] + vIdx);
    asset.vertices ~= Vertex([mesh.mVertices[vIdx].x, mesh.mVertices[vIdx].y, mesh.mVertices[vIdx].z]);
    mMesh.bounds.update(asset.vertices[$-1]);
    if (mesh.mNormals) {
      asset.vertices[gIdx].normal = [mesh.mNormals[vIdx].x, mesh.mNormals[vIdx].y,mesh.mNormals[vIdx].z];
    }
    if (mesh.mTextureCoords[texInfo.channel]) {
      asset.vertices[gIdx].texCoord = [mesh.mTextureCoords[texInfo.channel][vIdx].x, mesh.mTextureCoords[texInfo.channel][vIdx].y];
    }
    if (mesh.mColors[texInfo.channel]) {
      auto color = mesh.mColors[texInfo.channel][vIdx];
      asset.vertices[gIdx].color = [color.r, color.g, color.b, color.a];
    }
    asset.vertices[gIdx].tid = texInfo.tid;
    asset.LoadVertexBoneWeight(gIdx, weights, vIdx, app.bones);
  }

  // Load indices
  for (size_t f = 0; f < mesh.mNumFaces; f++) {
    auto face = &mesh.mFaces[f];
    for (size_t j = 0; j < face.mNumIndices; j++) {
      asset.indices ~= (mMesh.vertices[0] + face.mIndices[j]);
    }
  }
  asset.meshes[name(mesh.mName)] = mMesh;
  return(name(mesh.mName));
}

