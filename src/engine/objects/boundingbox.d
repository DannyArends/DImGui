/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : toMatrix, multiply, scale;
import vector : x, y, z, vSub, vAdd, vMul, midpoint;

/** BoundingBox */
class BoundingBox : Geometry {
  Bounds bounds;                                          /// Union world-AABB over all instances
  Bounds[] world;                                         /// Per-instance cached world-AABBs
  bool visible = true;                                    /// BoundingBox visible in frustum ?
  bool dirty = true;

  alias bounds this;

  this(){
   vertices = [
      Vertex([  0.0f, 0.0f, 0.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ]),

      Vertex([  0.0f, 0.0f, 0.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ])
    ];
    indices = [0, 1, 0, 3, 0, 4, 1, 2,
               1, 5, 2, 3, 2, 6, 3, 7,
               4, 5, 4, 7, 5, 6, 6, 7];
    instances = [DrawInstance()];
    topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    mName = typeof(this).stringof;
  };

  /** Compute world-space AABB from object-space bounds and instance matrix.
   * Uses OBB projection: transforms center, then sums absolute column extents. */
  @nogc pure Bounds boundsWorld(ref const Bounds l, size_t instance = 0) nothrow const {
    if(instances.length == 0 || instance >= instances.length) { return(Bounds.init); }
    auto m = instances[instance].matrix;
    float[3] c = m.multiply(midpoint(l.min, l.max));
    float[3] h = l.size.vMul(0.5f);
    float[3] e = [abs(m[0])*h[0] + abs(m[4])*h[1] + abs(m[8])*h[2],
                  abs(m[1])*h[0] + abs(m[5])*h[1] + abs(m[9])*h[2],
                  abs(m[2])*h[0] + abs(m[6])*h[1] + abs(m[10])*h[2]];
    return Bounds([c.vSub(e), c.vAdd(e)]);
  }

  /** World-space AABB for an instance using the box's cached local corners (no per-call vertex scan). */
  @nogc pure Bounds boundsWorld(size_t instance = 0) nothrow const {
    if(vertices.length < 8) return(Bounds.init);
    Bounds l = Bounds([vertices[0].position, vertices[6].position]);
    return(boundsWorld(l, instance));
  }

  @nogc pure void setDimensions(float[3] min, float[3] max) nothrow {
    vertices[0].position = [min[0], min[1], min[2]]; vertices[1].position = [max[0], min[1], min[2]];
    vertices[2].position = [max[0], max[1], min[2]]; vertices[3].position = [min[0], max[1], min[2]];
    vertices[4].position = [min[0], min[1], max[2]]; vertices[5].position = [max[0], min[1], max[2]];
    vertices[6].position = [max[0], max[1], max[2]]; vertices[7].position = [min[0], max[1], max[2]];
  }
}

/**  Compute the bounding box for object */
void computeBoundingBox(T)(ref T object, bool verbose = false) {
  if(object.box is null) { object.box = new BoundingBox(); }
  if(!object.box.dirty) return;
  if(verbose) SDL_Log("Updating %s(%s) VERTEX", toStringz(object.box.geometry()), toStringz(object.geometry()));

  if(object.vertices.needsBuffer || object.box.vertices.length < 8) {
    Bounds bounds;
    for (size_t i = 0; i < object.vertices.length; i++) { bounds.update(object.vertices[i].position); }
    object.box.setDimensions(bounds.min, bounds.max);
    object.box.vertices.invalidate();
  }
  Bounds local = Bounds([object.box.vertices[0].position, object.box.vertices[6].position]);

  object.box.instances = object.instances.dup;
  object.box.instances.invalidate();

  object.box.bounds = Bounds.init; // Reset bounds
  if(object.box.world.length < object.box.instances.length) { object.box.world.length = object.box.instances.length; }
  foreach(i; 0 .. object.box.instances.length) {
    object.box.world[i] = object.box.boundsWorld(local, i);
    object.box.bounds.update(object.box.world[i]);
  }
  object.box.dirty = false;
}

/** Compute / update the global scene bounds with an assimp node */
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

/** Compute assimp scale adjustment based on global scene bounds */
Matrix computeScaleAdjustment(const Bounds bounds){
  float[3] size = bounds.size();
  float maxDim = fmax(size.x, fmax(size.y, size.z));
  float scaleFactor = (maxDim > 0) ? 4.0f / maxDim : 4.0f; // Scale to unit cube

  Matrix scaleToFit = scale(Matrix(), [scaleFactor, scaleFactor, scaleFactor]);
  return(scaleToFit);
}
