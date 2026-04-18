/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : OpenAsset, name;
import bone : Bone, BoneWeights, loadBoneWeights;
import material : getChannel;
import matrix : Matrix, multiply, inverse, transpose;
import vector : euclidean, cross, dot, x, y, z;
import vertex : Vertex, INSTANCE;

struct Mesh {
  int[2] vertices;  /// Start .. End positions in Geometry.vertices array
  int mid = -1;               /// Mesh Material ID
  int tid = -1;               /// Mesh DIFFUSE ID
  int nid = -1;               /// Mesh NORMALS ID
  int oid = -1;               /// Mesh OPACITY ID
}

struct MeshList {
  Mesh[] meshInfo;            /// Meshes for GPU SSBO
  ulong capacity = 256;       /// GPU SSBO capacity
  alias meshInfo this;
}

void logMesh(uint i, const Mesh m, const(char)* prefix = "meshInfo") {
  SDL_Log("%s[%d] v=[%d,%d] mid=%d tid=%d nid=%d oid=%d", prefix, i, m.vertices[0], m.vertices[1], m.mid, m.tid, m.nid, m.oid);
}

void printMeshInfo(const App app) { if(!app.trace){ return; } foreach(i, ref m; app.meshes) logMesh(cast(uint)i, m); }

void updateMeshInfo(ref App app) {
  app.meshes.length = 0;
  bool needsUpdate = false;
  for (size_t o = 0; o < app.objects.length; o++) {
    uint newBase = cast(uint)app.meshes.length;
    uint size    = cast(uint)app.objects[o].meshes.length;
    if (app.objects[o].perInstanceMeshDef) {
      // Append meshes in sorted key order so TileType enum value == relative index
      auto sortedKeys = app.objects[o].meshes.keys.sort;
      foreach (k; sortedKeys) app.meshes ~= app.objects[o].meshes[k];
      if (app.objects[o].meshBase != newBase) {
        foreach (ref inst; app.objects[o].instances) {
          if (app.objects[o].meshBase == uint.max) {
            // First time: instances carry relative indices, make absolute
            inst.meshdef[0] += newBase;
            inst.meshdef[1] += newBase;
          } else {
            // Base shifted: apply delta
            int delta = cast(int)newBase - cast(int)app.objects[o].meshBase;
            inst.meshdef[0] = cast(uint)(cast(int)inst.meshdef[0] + delta);
            inst.meshdef[1] = cast(uint)(cast(int)inst.meshdef[1] + delta);
          }
        }
        app.objects[o].meshBase = newBase;
        app.objects[o].buffers[INSTANCE] = false;
        needsUpdate = true;
      }
    } else {
      uint[2] expected = [newBase, newBase + size];
      if (app.objects[o].instances.length > 0 && app.objects[o].instances[0].meshdef != expected) {
        foreach (ref inst; app.objects[o].instances) inst.meshdef = expected;
        app.objects[o].buffers[INSTANCE] = false;
        needsUpdate = true;
      }
      app.meshes ~= app.objects[o].meshes.values;
    }
  }
  // Grow SSBO capacity if needed
  if(app.meshes.length > app.meshes.capacity) {
    while(app.meshes.capacity < app.meshes.length) app.meshes.capacity *= 2;
    app.meshes.length = app.meshes.capacity;
    app.rebuild = true;
  }
  // Update SSBO
  if(needsUpdate) {
    foreach(si; 0..app.framesInFlight) {
      if(si == app.syncIndex) continue;
      vkWaitForFences(app.device, 1, &app.fences[si].renderInFlight, true, ulong.max);
    }
    app.buffers["MeshMatrices"].dirty[] = true;
    app.printMeshInfo();
  }
}

string loadMesh(aiMesh* mesh, ref OpenAsset asset, const Matrix gTransform, bool verbose = false) {
  if (verbose) {
    SDL_Log("Mesh: %s", toStringz(name(mesh.mName)));
    SDL_Log(" - %u vertices, %u faces, %u bones", mesh.mNumVertices, mesh.mNumFaces, mesh.mNumBones);
    SDL_Log(" - %u / %u material", mesh.mMaterialIndex, asset.materials.length);
  }
  // Vertex offset, load texture information,  bone weight, and normal matrix
  size_t vOff = asset.vertices.length;
  auto channel = getChannel(asset, mesh.mMaterialIndex, aiTextureType_DIFFUSE);
  auto weights = asset.loadBoneWeights(mesh, asset.bones, gTransform);
  auto normMatrix = gTransform.inverse().transpose();

  // TODO first create a Material definition for the object => add to app.materials
  // Then use OUR internal material index (app.materials)
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
      asset.vertices[gIdx].color = [color.r, color.g, color.b, color.a];
    }
    if (mesh.mTangents && mesh.mBitangents) {
      float[3] T = [mesh.mTangents[vIdx].x, mesh.mTangents[vIdx].y, mesh.mTangents[vIdx].z];
      float[3] B = [mesh.mBitangents[vIdx].x, mesh.mBitangents[vIdx].y, mesh.mBitangents[vIdx].z];
      float[3] N = asset.vertices[gIdx].normal;
      float w = (cross(N, T).dot(B) < 0.0f) ? -1.0f : 1.0f;
      asset.vertices[gIdx].tangent = [T[0], T[1], T[2], w];
    }
    asset.assignBoneWeight(gIdx, weights, vIdx, asset.bones);
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
