/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : destroyGeometryBuffers, nameGeometryBuffer, toGPU;
import boundingbox : computeBoundingBox;
import matrix : position, transpose, translate, rotate, scale, inverse;
import textures : idx;
import vector : vSub, vAdd, dot, vMul, cross, normalize, euclidean;

/** An instance of a Geometry
 */
struct Instance {
  uint[2] meshdef = [0, 0];  // Start, End
  Matrix matrix;
  alias matrix this;
}

shared uint guid = 1;

/** A Geometry that can be rendered
 */
class Geometry {
  GeometryBuffer vertexBuffer;
  GeometryBuffer indexBuffer;
  GeometryBuffer instanceBuffer;
  VkFence fence;                                /// Fence to complete before destoying the object

  Vertex[] vertices;                            /// Vertices of type Vertex stored on the CPU
  uint[] indices;                               /// Indices of type uint stored on the CPU
  Instance[] instances;                         /// Instance array
  alias instances this;

  uint uid;
  Node rootnode;                                /// OpenAsset Root
  string mName;                                 /// OpenAsset name
  MetaData mData;                               /// OpenAsset metaData
  Bounds bounds;                                /// OpenAsset bounding box

  Animation[] animations;                       /// Animations
  uint animation = 0;                           /// Current Animation
  Mesh[string] meshes;                          /// Meshes
  Material[] materials;                         /// Materials

  BoundingBox box = null;                       /// Bounding Box
  bool window = false;                          /// ImGui window displayed?

  @nogc this() nothrow {
    uid = guid;
    atomicOp!"+="(guid, 1);
  }

  /** Allocate vertex, index, and instance buffers */
  void buffer(ref App app, VkCommandBuffer cmdBuffer) {
    if(app.trace) SDL_Log("Buffering: %s", toStringz(name()));
    if(!buffers[VERTEX] && vertices.length > 0) {
      buffers[VERTEX] = app.toGPU(vertices, vertexBuffer, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
      app.nameGeometryBuffer(vertexBuffer, "VERTEX", name());
    }
    if(!buffers[INDEX] && indices.length > 0){
      buffers[INDEX] = app.toGPU(indices, indexBuffer, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
      app.nameGeometryBuffer(indexBuffer, "INDEX", name());
    }
    if(!buffers[INSTANCE] && instances.length > 0){
      buffers[INSTANCE] = app.toGPU(instances, instanceBuffer, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
      app.nameGeometryBuffer(instanceBuffer, "INSTANCE", name());
    }
  }

  bool isVisible = true;                           /// Boolean flag
  bool deAllocate = false;                          /// Boolean flag
  bool[3] buffers = [false, false, false];          /// Boolean flag
  @property @nogc bool isBuffered() nothrow {
    return(buffers[VERTEX] && buffers[INDEX] && buffers[INSTANCE]); 
  }

  VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;  /// Vulkan render topology (selects Pipeline)

  void function(ref App app, ref Geometry obj, SDL_Event e) onMouseEnter;
  void function(ref App app, ref Geometry obj, SDL_Event e) onMouseExit;
  void function(ref App app, ref Geometry obj, SDL_Event e) onMouseDown;
  void function(ref App app, ref Geometry obj, SDL_Event e) onMouseUp;
  void function(ref App app, ref Geometry obj, SDL_Event e) onMouseOver;
  void function(ref App app, ref Geometry obj, SDL_Event e) onMouseMove;
  void function(ref App app, ref Geometry obj, float dt) onFrame;
  void function(ref App app, ref Geometry obj) onTick;
  string function() name;
}

struct Geometries {
  Geometry[] array;
  bool loaded = false; /// Are we loading a texture a-sync ?
  alias array this;
}

void bufferGeometries(ref App app, ref VkCommandBuffer cmd){
  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.showBounds) {
      app.objects[x].computeBoundingBox(app.trace);
      app.objects[x].box.buffer(app, cmd);
    }
    if(!app.objects[x].isBuffered) {
      if(app.trace) SDL_Log("Buffer object: %d %p", x, app.objects[x]);
      app.objects[x].buffer(app, cmd);
    }
  }
}

/** Set position of instance from object.instances by p */
@nogc void position(T)(T object, float[3] p, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  object.instances[instance] = position(object.instances[instance], p);
  object.buffers[INSTANCE] = false;
}

@nogc float[3] position(T)(T object, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  return(position(object.instances[instance]));
}

/** Rotate instance from object.instances by r */
@nogc void rotate(T)(T object, float[3] r, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  object.instances[instance] = rotate(object.instances[instance], r);
  object.buffers[INSTANCE] = false;
}

/** Scale instance from object.instances by s */
@nogc void scale(T)(T object, float[3] s, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  object.instances[instance] = scale(object.instances[instance], s);
  object.buffers[INSTANCE] = false;
}

float scale(T)(T object, uint instance = 0) {
  assert(instance <  object.instances.length, "No such instance");
  return(scale(object.instances[instance]));
}

/** Set tid for instance from object.instances to Texture name 
 */
void texture(T)(T object, string name, string mname = "") {
  if(object.materials.length == 0){
    object.materials.length = 1;
    object.materials[0] = Material(name, [aiTextureType_DIFFUSE: TexureInfo(name) ]);
  }else{
    object.materials[0].textures[aiTextureType_DIFFUSE] = TexureInfo(name);
  }
  foreach(ref mesh ; object.meshes) { mesh.mid = 0; }
}

void bumpmap(T)(T object, string name, string mname = "") {
  if(object.materials.length == 0){
    object.materials.length = 1;
    object.materials[0] = Material(name, [aiTextureType_NORMALS: TexureInfo(name) ]);
  }else{
    object.materials[0].textures[aiTextureType_NORMALS] = TexureInfo(name);
  }
  foreach(ref mesh ; object.meshes) { mesh.mid = 0; }
}

void opacity(T)(T object, string name, string mname = "") {
  if(object.materials.length == 0){
    object.materials.length = 1;
    object.materials[0] = Material(name, [aiTextureType_OPACITY: TexureInfo(name) ]);
  }else{
    object.materials[0].textures[aiTextureType_OPACITY] = TexureInfo(name);
  }
  foreach(ref mesh ; object.meshes) { mesh.oid = 0; }
}

/** Euclidean distance between Geometry and Camera */
@nogc float distance(T)(const T object, const Camera camera) nothrow { 
  return euclidean(object.instances[0].getTranslation(), camera.position); 
}

/** Cleanup all GPU buffers, now */
void cleanup(ref App app, Geometry object) {
  app.destroyGeometryBuffers(object.vertexBuffer);
  app.destroyGeometryBuffers(object.indexBuffer);
  app.destroyGeometryBuffers(object.instanceBuffer);
  if(object.box){ app.cleanup(object.box); }
}

/** deAllocate all GPU buffers after waiting for the object to not be in use anymore */
void deAllocate(ref App app, Geometry object) {
  // We use the vertex buffer fence to wait until the buffers aren't in-use anymore
  object.vertexBuffer.frame = app.totalFramesRendered + app.framesInFlight;
  app.bufferDeletionQueue.add((bool force){
    if (force || (app.totalFramesRendered >= object.vertexBuffer.frame)){ app.cleanup(object); return(true); }
    return(false);
  });
}

/** Add a vertex to a geometry of the object */
uint addVertex(ref Geometry geometry, const Vertex v) nothrow {
  geometry.vertices ~= v;
  geometry.buffers[VERTEX] = false;
  return(cast(uint)(geometry.vertices.length-1));
}

void setColor(T)(ref T geometry, float[4] color = [1.0f, 0.0f, 0.0f, 1.0f]){
  for (uint x = 0; x < geometry.vertices.length; x++) {
    geometry.vertices[x].color = color;
  }
  geometry.buffers[VERTEX] = false;
}

/** Get all the triangle faces of a geometry */
pure uint[3][] faces(const Geometry geometry) nothrow {
  uint[3][] fList;
  if(geometry.indices.length <= 2) return(fList); // Objects (e.g. lines) can have less elements than a triangle 
  fList.length = (geometry.indices.length - 2);
  for (uint i = 0, x = 0; x < (geometry.indices.length - 2); x += 3, i++) {
    fList[i] = [geometry.indices[x], geometry.indices[x+1], geometry.indices[x+2]]; // Add to the faces list
  }
  return(fList);
}

/** Compute normal vectors of a Geometry */
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
    if (abs(det) < 0.001f) continue;
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
    geometry.vertices[i].tangent = finalTangent;
  }

  geometry.buffers[VERTEX] = false; // Mark vertex buffer as dirty, needs re-upload
  if(verbose) SDL_Log("computeTangents %d vertex tangents computed", geometry.vertices.length);
}

/** Render a Geometry to app.renderBuffers[i] */
void draw(T)(ref App app, ref T object, size_t i) {
  if(!object.isBuffered()) return;
  if(app.trace) SDL_Log("DRAW: %d instances", object.instances.length);

  VkDeviceSize[] offsets = [0];

  vkCmdBindVertexBuffers(app.renderBuffers[i], VERTEX, 1, &object.vertexBuffer.vb, &offsets[0]);
  vkCmdBindVertexBuffers(app.renderBuffers[i], INSTANCE, 1, &object.instanceBuffer.vb, &offsets[0]);
  vkCmdBindIndexBuffer(app.renderBuffers[i], object.indexBuffer.vb, 0, VK_INDEX_TYPE_UINT32);

  vkCmdDrawIndexed(app.renderBuffers[i], cast(uint)object.indices.length, cast(uint)object.instances.length, 0, 0, 0);
  if(app.trace) SDL_Log("DRAW[%s]: DONE", toStringz(object.name()));
}

/** Render a Geometry to app.renderBuffers[i] */
void shadow(ref App app, Geometry object, size_t i) {
  if(object.vertexBuffer.vb == null || object.instanceBuffer.vb == null) return;
  if(app.trace) SDL_Log("SHADOW[%s]: %d instances", toStringz(object.name()), object.instances.length);
  VkDeviceSize[] offsets = [0];

  vkCmdBindVertexBuffers(app.shadowBuffers[i], VERTEX, 1, &object.vertexBuffer.vb, &offsets[0]);
  vkCmdBindVertexBuffers(app.shadowBuffers[i], INSTANCE, 1, &object.instanceBuffer.vb, &offsets[0]);
  vkCmdBindIndexBuffer(app.shadowBuffers[i], object.indexBuffer.vb, 0, VK_INDEX_TYPE_UINT32);

  vkCmdDrawIndexed(app.shadowBuffers[i], cast(uint)object.indices.length, cast(uint)object.instances.length, 0, 0, 0);
  if(app.trace) SDL_Log("SHADOW[%s]: DONE", toStringz(object.name()));
}
