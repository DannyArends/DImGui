/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : toMatrix, multiply, scale;
import vector : x,y,z;

struct Bounds {
  float[3] min = [ float.max, float.max, float.max];
  float[3] max = [-float.max,-float.max,-float.max];

  @nogc pure void update(const float[3] v) nothrow {
    if (v.x < min[0]) min[0] = v.x;
    if (v.y < min[1]) min[1] = v.y;
    if (v.z < min[2]) min[2] = v.z;

    if (v.x > max[0]) max[0] = v.x;
    if (v.y > max[1]) max[1] = v.y;
    if (v.z > max[2]) max[2] = v.z;
  }
  
  @property @nogc pure float[3] size() nothrow const { float[3] s = max[] - min[]; return(s); }
}

/** BoundingBox
 */
class BoundingBox : Geometry {
  this(){
   vertices = [
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),

      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ])
    ];
    indices = [0, 1,  0, 3,  0, 4,  1, 2, 
               1, 5,  2, 3,  2, 6,  3, 7, 
               4, 5,  4, 7,  5, 6,  6, 7];
    instances = [Instance()];
    topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
  };

  @property @nogc pure float[3] min() nothrow const { return(vertices[0].position); }
  @property @nogc pure float[3] max() nothrow const { return(vertices[6].position); }

  @property @nogc pure float[3] scale() nothrow const {
    float[3] scale = vertices[0].position[] - vertices[6].position[];
    return(scale);
  }

  @nogc pure void setDimensions(float[3] min, float[3] max) nothrow {
    vertices[0].position = [min[0], min[1], min[2]]; vertices[1].position = [max[0], min[1], min[2]];
    vertices[2].position = [max[0], max[1], min[2]]; vertices[3].position = [min[0], max[1], min[2]];
    vertices[4].position = [min[0], min[1], max[2]]; vertices[5].position = [max[0], min[1], max[2]];
    vertices[6].position = [max[0], max[1], max[2]]; vertices[7].position = [min[0], max[1], max[2]];
  }

  @property @nogc pure float[3] center() nothrow const {
    float[3] mid = (vertices[0].position[] + vertices[6].position[]) / 2.0f;
    return(mid);
  }
}

/**  Compute the bounding box for object
 */
void computeBoundingBox(T)(ref T object, bool verbose = false) {
  bool initial = false;
  if(object.box is null) {
    if(verbose) SDL_Log("Computing new Bounding Box for %s", toStringz(object.name()));
    object.box = new BoundingBox();
    initial = true;
  }
  object.box.name = (){ return("BoundingBox"); };

  if(initial || !object.buffers[VERTEX]) { // The object vertex buffer is out of date, update the BoundingBox vertices
    if(verbose) SDL_Log("Updating %s(%s) VERTEX", toStringz(object.box.name()), toStringz(object.name()));
    Bounds bounds;
    for (size_t i = 0; i < object.vertices.length; i++) { bounds.update(object.vertices[i].position); }
    object.box.setDimensions(bounds.min, bounds.max);
    object.box.buffers[VERTEX] = false;
  }
  if(initial || !object.buffers[INSTANCE]) { // The object instance buffer is out of date, update the BoundingBox instances
    if(verbose) SDL_Log("Updating %s(%s) INSTANCE", toStringz(object.box.name()), toStringz(object.name()));
    object.box.instances.length = object.instances.length;
    for(size_t x = 0; x < object.instances.length; x++) {
      object.box.instances[x].matrix = object.instances[x].matrix;
    }
    object.box.buffers[INSTANCE] = false;
  }
}

/** Compute/Update the global scene bounds with an assimp node
 */
void calculateBounds(ref Bounds bounds, aiScene* scene, aiNode* node, const Matrix pTransform) {
  Matrix gTransform = pTransform.multiply(toMatrix(node.mTransformation));
  for (uint i = 0; i < node.mNumMeshes; ++i) {
    aiMesh* mesh = scene.mMeshes[node.mMeshes[i]];
    for (uint j = 0; j < mesh.mNumVertices; ++j) {
      float[3] position = gTransform.multiply([mesh.mVertices[j].x, mesh.mVertices[j].y, mesh.mVertices[j].z]);
      bounds.update(position);
    }
  }
  for (uint i = 0; i < node.mNumChildren; ++i) { bounds.calculateBounds(scene, node.mChildren[i], gTransform); }
}

/** Compute assimp scale adjustment based on global scene bounds
 */
Matrix computeScaleAdjustment(const Bounds bounds){
  float[3] size = bounds.size();
  float maxDim = fmax(size.x, fmax(size.y, size.z));
  float scaleFactor = (maxDim > 0) ? 4.0f / maxDim : 4.0f; // Scale to unit cube

  Matrix scaleToFit = scale(Matrix(), [scaleFactor, scaleFactor, scaleFactor]);
  return(scaleToFit);
}
