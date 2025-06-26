/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : Geometry;
import vector : x,y,z;
import vertex : Vertex;
import matrix : Matrix, toMatrix, multiply, scale;

struct Bounds {
  float[3] min = [ float.max, float.max, float.max];
  float[3] max = [-float.max,-float.max,-float.max];
}

void update(ref Bounds b, const float[3] v){
  if (v.x < b.min[0]) b.min[0] = v.x;
  if (v.y < b.min[1]) b.min[1] = v.y;
  if (v.z < b.min[2]) b.min[2] = v.z;

  if (v.x > b.max[0]) b.max[0] = v.x;
  if (v.y > b.max[1]) b.max[1] = v.y;
  if (v.z > b.max[2]) b.max[2] = v.z;
}

void calculateBounds(ref Bounds bounds, aiScene* scene, aiNode* node, Matrix pTransform) {
  Matrix gTransform = pTransform.multiply(toMatrix(node.mTransformation));
  for (uint i = 0; i < node.mNumMeshes; ++i) {
    aiMesh* mesh = scene.mMeshes[node.mMeshes[i]];
    for (uint j = 0; j < mesh.mNumVertices; ++j) {
      float[3] position = gTransform.multiply([mesh.mVertices[j].x, mesh.mVertices[j].y, mesh.mVertices[j].z]);
      bounds.update(position);
    }
  }

  for (uint i = 0; i < node.mNumChildren; ++i) {
    bounds.calculateBounds(scene, node.mChildren[i], gTransform);
  }
}

Matrix computeScaleAdjustment(Bounds bounds){
  float[3] minP = [bounds.min[0], bounds.min[1], bounds.min[2]];
  float[3] maxP = [bounds.max[0], bounds.max[1], bounds.max[2]];
  float[3] size = maxP[] - minP[];
  float maxDim = fmax(size.x, fmax(size.y, size.z));
  float scaleFactor = (maxDim > 0) ? 4.0f / maxDim : 4.0f; // Scale to unit cube

  Matrix scaleToFit = scale(Matrix(), [scaleFactor, scaleFactor, scaleFactor]);
  return(scaleToFit);
}

