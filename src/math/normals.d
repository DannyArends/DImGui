/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

import vector : vSub, vAdd, vMul, cross, normalize, dot;
import vertex : VERTEX;

/** Get all the triangle faces of a geometry */
pure uint[3][] faces(T)(const T geometry) nothrow {
  uint[3][] fList;
  if(geometry.indices.length <= 2) return(fList); // Objects (e.g. lines) can have less elements than a triangle 
  fList.length = (geometry.indices.length - 2);
  for (uint i = 0, x = 0; x < (geometry.indices.length - 2); x += 3, i++) {
    fList[i] = [geometry.indices[x], geometry.indices[x+1], geometry.indices[x+2]]; // Add to the faces list
  }
  return(fList);
}

/** Compute Normal vectors of a Geometry */
void computeNormals(T)(ref T geometry, bool invert = false, bool verbose = false) {
  auto faces = geometry.faces;
  float[3][] normals = new float[3][faces.length];
  auto cnt = 0;
  foreach (uint[3] face; faces) {
    auto edge1 = geometry.vertices[face[1]].position.vSub(geometry.vertices[face[0]].position);
    auto edge2 = geometry.vertices[face[2]].position.vSub(geometry.vertices[face[0]].position);
    auto cp = cross(edge1, edge2);
    normals[cnt] = cp.normalize();
    cnt++;
  }
  for (size_t i = 0; i < geometry.vertices.length; i++) {  // Set all normals to 0
    geometry.vertices[i].normal = [0.0f, 0.0f, 0.0f];
  }
  foreach (size_t i, uint[3] face; faces) {    // Sum triangle normals per vertex
    geometry.vertices[face[0]].normal = geometry.vertices[face[0]].normal.vAdd(normals[i]);
    geometry.vertices[face[1]].normal = geometry.vertices[face[1]].normal.vAdd(normals[i]);
    geometry.vertices[face[2]].normal = geometry.vertices[face[2]].normal.vAdd(normals[i]);
  }
  for (size_t i = 0; i < geometry.vertices.length; i++) {  // Normalize each normal
    geometry.vertices[i].normal.normalize();
    if(invert) geometry.vertices[i].normal[] = -geometry.vertices[i].normal[];
  }
  geometry.buffers[VERTEX] = false;
  if(verbose) SDL_Log("computeNormals %d vertex normals computed\n", geometry.vertices.length);
}

/** Compute Tangent vectors of a Geometry */
void computeTangents(T)(ref T geometry, bool verbose = false) {
  auto faces = geometry.faces;

  if (faces.length == 0 || geometry.vertices.length == 0) {
    SDL_Log("computeTangents: Geometry has no faces or vertices.");
    return;
  }

  float[3][] tan1 = new float[3][geometry.vertices.length];
  float[3][] tan2 = new float[3][geometry.vertices.length];
  for (size_t i = 0; i < geometry.vertices.length; ++i) {
    tan1[i] = [0.0f, 0.0f, 0.0f][]; // Vectorized zeroing
    tan2[i] = [0.0f, 0.0f, 0.0f][]; // Vectorized zeroing
  }

  foreach (const uint[3] face; faces) {
    if (face[0] >= geometry.vertices.length || face[1] >= geometry.vertices.length || face[2] >= geometry.vertices.length) {
      SDL_Log("computeTangents: Invalid index found in face.");
      continue;
    }

    // Get positions and UVs of the triangle vertices
    auto v1 = geometry.vertices[face[0]].position;
    auto v2 = geometry.vertices[face[1]].position;
    auto v3 = geometry.vertices[face[2]].position;

    auto w1 = geometry.vertices[face[0]].texCoord;
    auto w2 = geometry.vertices[face[1]].texCoord;
    auto w3 = geometry.vertices[face[2]].texCoord;

    // Calculate edges of the triangle in 3D space
    auto edge1 = v2.vSub(v1);
    auto edge2 = v3.vSub(v1);

    // Calculate UV differences
    float x1 = w2[0] - w1[0];
    float y1 = w2[1] - w1[1];
    float x2 = w3[0] - w1[0];
    float y2 = w3[1] - w1[1];

    float det = (x1 * y2 - x2 * y1);
    if (abs(det) < 1e-6f) continue;
    float r = 1.0f / det;

    if (!isFinite(r) || isNaN(r)) { // Ensure r is a valid finite number
      SDL_Log("computeTangents: Non-finite or NaN determinant encountered.");
      continue;
    }

    auto sdir = (edge1.vMul(y2)).vSub(edge2.vMul(y1)).vMul(r);
    auto tdir = (edge2.vMul(x1)).vSub(edge1.vMul(x2)).vMul(r);

    tan1[face[0]] = tan1[face[0]].vAdd(sdir);
    tan1[face[1]] = tan1[face[1]].vAdd(sdir);
    tan1[face[2]] = tan1[face[2]].vAdd(sdir);

    tan2[face[0]] = tan2[face[0]].vAdd(tdir);
    tan2[face[1]] = tan2[face[1]].vAdd(tdir);
    tan2[face[2]] = tan2[face[2]].vAdd(tdir);
  }

  for (size_t i = 0; i < geometry.vertices.length; ++i) {
    auto n = geometry.vertices[i].normal;
    auto t = tan1[i];
    float[3] finalTangent = (t.vSub(n.vMul(n.dot(t)))).normalize();
    float[3] bitangent = tan2[i].normalize();
    float handedness = (cross(n, finalTangent).dot(bitangent) < 0.0f) ? -1.0f : 1.0f;
    geometry.vertices[i].tangent = [finalTangent[0], finalTangent[1], finalTangent[2], handedness];
  }

  geometry.buffers[VERTEX] = false; // Mark vertex buffer as dirty, needs re-upload
  if(verbose) SDL_Log("computeTangents %d vertex tangents computed", geometry.vertices.length);
}
