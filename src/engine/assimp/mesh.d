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
import vertex : Vertex, INSTANCE;

struct Mesh {
  align(16) int[2] vertices;  /// Start .. End positions in Geometry.vertices array
  int tid = -1;               /// Mesh DIFFUSE ID
  int nid = -1;               /// Mesh NORMALS ID
  int oid = -1;               /// Mesh OPACITY ID
}

void updateMeshInfo(ref App app) {
  app.meshInfo.length = 0;
  for (size_t o = 0; o < app.objects.length; o++) {
    uint size = cast(uint)app.objects[o].meshes.array.length;
    for (size_t i = 0; i < app.objects[o].instances.length; i++) {  // Load faces to indices
      app.objects[o].instances[i].meshdef = [cast(uint)app.meshInfo.length, cast(uint)app.meshInfo.length + size];
      app.objects[o].buffers[INSTANCE] = false;
    }
    app.meshInfo ~= app.objects[o].meshes.array;
  }
}

string loadMesh(ref App app, aiMesh* mesh, ref OpenAsset asset, const Matrix gTransform) {
  if (app.verbose) {
    SDL_Log("Mesh: %s", toStringz(name(mesh.mName)));
    SDL_Log(" - %u vertices, %u faces, %u bones", mesh.mNumVertices, mesh.mNumFaces, mesh.mNumBones);
    SDL_Log(" - %u / %u material", mesh.mMaterialIndex, asset.materials.length);
  }
  // Vertex offset, load texture information,  bone weight, and normal matrix
  size_t vOff = asset.vertices.length;
  auto baseTexture = app.matchTexture(asset, mesh.mMaterialIndex, aiTextureType_DIFFUSE);
  auto normTexture = app.matchTexture(asset, mesh.mMaterialIndex, aiTextureType_NORMALS);
  auto opacTexture = app.matchTexture(asset, mesh.mMaterialIndex, aiTextureType_OPACITY);
  if (app.verbose) SDL_Log(" - %d | %d | %d texture.ids", baseTexture.tid, normTexture.tid, opacTexture.tid);
  
  auto weights = asset.loadBones(mesh, app.bones, gTransform);
  auto normMatrix = gTransform.inverse().transpose();

  // TODO first create a Material definition for the object => add to app.materials
  // Then use OUR internal material index (app.materials)
  Mesh mMesh = Mesh([cast(uint)(asset.vertices.length), cast(uint)(asset.vertices.length) + mesh.mNumVertices], 
                     baseTexture.tid, normTexture.tid, opacTexture.tid);

  for (size_t vIdx = 0; vIdx < mesh.mNumVertices; vIdx++) {  // Load vertex information
    size_t gIdx = (vOff + vIdx);
    asset.vertices ~= Vertex(gTransform.multiply([mesh.mVertices[vIdx].x, mesh.mVertices[vIdx].y, mesh.mVertices[vIdx].z]));

    if (mesh.mNormals) {
      asset.vertices[gIdx].normal = normMatrix.multiply([mesh.mNormals[vIdx].x, mesh.mNormals[vIdx].y,mesh.mNormals[vIdx].z]);
    }
    if (mesh.mTextureCoords[baseTexture.channel]) {
      asset.vertices[gIdx].texCoord = [mesh.mTextureCoords[baseTexture.channel][vIdx].x, mesh.mTextureCoords[baseTexture.channel][vIdx].y];
    }
    if (mesh.mColors[baseTexture.channel]) {
      auto color = mesh.mColors[baseTexture.channel][vIdx];
      asset.vertices[gIdx].color = [color.r, color.g, color.b, color.a];
    }
    if (mesh.mTangents) {
      asset.vertices[gIdx].tangent = [mesh.mTangents[vIdx].x, mesh.mTangents[vIdx].y, mesh.mTangents[vIdx].z];
    }
    asset.assignBoneWeight(gIdx, weights, vIdx, app.bones);
  }

  for (size_t f = 0; f < mesh.mNumFaces; f++) {  // Load faces to indices
    auto face = &mesh.mFaces[f];
    for (size_t j = 0; j < face.mNumIndices; j++) {
      asset.indices ~= cast(uint)(vOff + face.mIndices[j]);
    }
  }
  string meshName = format("%s:%d", name(mesh.mName), asset.meshes.length);
  asset.meshes[meshName] = mMesh;
  return(meshName);
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
