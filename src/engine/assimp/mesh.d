/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : name;
import bone : loadBoneWeights, synthesizeBone;
import amat : getChannel;
import material : ensureMaterial;
import matrix : multiply, inverse, transpose;
import vector : euclidean, cross, dot, x, y, z;

struct Mesh {
  int[2] vertices;        /// Start .. End positions in Geometry.vertices array
  int mid = -1;           /// Mesh Material ID
  int mat = -1;           /// assimp-local material index
}

void updateMeshInfo(ref App app) {
  for (size_t o = 0; o < app.objects.length; o++) {
    if (app.objects[o].instancedMesh && app.objects[o].boneCount == 0) continue;
    app.ensureMaterial(app.objects[o]);
  }
}

string loadMesh(aiMesh* mesh, ref OpenAsset asset, const Matrix gTransform, string ownerNode = null, bool verbose = false) {
  if (verbose) {
    SDL_Log("Mesh: %s", toStringz(name(mesh.mName)));
    SDL_Log(" - %u vertices, %u faces, %u bones", mesh.mNumVertices, mesh.mNumFaces, mesh.mNumBones);
    SDL_Log(" - %u / %u material", mesh.mMaterialIndex, asset.materials.length);
  }
  // Vertex offset, load texture information,  bone weight, and normal matrix
  size_t vOff = asset.vertices.length;
  auto channel = getChannel(asset, mesh.mMaterialIndex, aiTextureType_DIFFUSE);
  auto weights = asset.loadBoneWeights(mesh, asset.bones, gTransform);
  int synthBone = (weights.length == 0) ? asset.synthesizeBone(ownerNode, gTransform) : -1;
  auto normMatrix = gTransform.inverse().transpose();

  Mesh mMesh = Mesh([cast(uint)(asset.vertices.length), cast(uint)(vOff) + mesh.mNumVertices],  mesh.mMaterialIndex);

  for (size_t vIdx = 0; vIdx < mesh.mNumVertices; vIdx++) {  // Load vertex information
    size_t gIdx = (vOff + vIdx);
    asset.vertices ~= Vertex(gTransform.multiply([mesh.mVertices[vIdx].x, mesh.mVertices[vIdx].y, mesh.mVertices[vIdx].z]));

    if (mesh.mNormals) {
      asset.vertices[gIdx].normal = normMatrix.multiply([mesh.mNormals[vIdx].x, mesh.mNormals[vIdx].y,mesh.mNormals[vIdx].z]);
    }
    if (mesh.mTextureCoords[channel]) {
      asset.vertices[gIdx].texCoord = [mesh.mTextureCoords[channel][vIdx].x, mesh.mTextureCoords[channel][vIdx].y];
    }
    if (mesh.mColors[channel]) {
      auto color = mesh.mColors[channel][vIdx];
      //asset.vertices[gIdx].color = [color.r, color.g, color.b, color.a];
    }
    if (mesh.mTangents && mesh.mBitangents) {
      float[3] T = [mesh.mTangents[vIdx].x, mesh.mTangents[vIdx].y, mesh.mTangents[vIdx].z];
      float[3] B = [mesh.mBitangents[vIdx].x, mesh.mBitangents[vIdx].y, mesh.mBitangents[vIdx].z];
      float[3] N = asset.vertices[gIdx].normal;
      float w = (cross(N, T).dot(B) < 0.0f) ? -1.0f : 1.0f;
      asset.vertices[gIdx].tangent = [T[0], T[1], T[2], w];
    }

    if (synthBone >= 0) {
      asset.vertices[gIdx].bones[0] = cast(uint)synthBone;
      asset.vertices[gIdx].weights[0] = 1.0f;
    }else {
      asset.assignBoneWeight(gIdx, weights, vIdx, asset.bones);
    }
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
