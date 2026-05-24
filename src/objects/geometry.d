/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : destroyGeometryBuffers, nameGeometryBuffer, toGPU;
import boundingbox : computeBoundingBox;
import textures : idx;
import mesh : logMesh;
import normals : computeNormals, computeTangents;

shared uint guid = 1;

/** A Geometry that can be rendered */
class Geometry {
  GeometryBuffer vertexBuffer;
  GeometryBuffer indexBuffer;
  GeometryBuffer instanceBuffer;
  VkFence fence;                                /// Fence to complete before destoying the object

  Vertex[] vertices;                            /// Vertices of type Vertex stored on the CPU
  uint[] indices;                               /// Indices of type uint stored on the CPU
  DrawInstance[] instances;                     /// Instance array
  alias instances this;

  uint uid;
  Node rootnode;                                /// OpenAsset Root
  string mName;                                 /// OpenAsset name
  MetaData mData;                               /// OpenAsset metaData
  Bounds bounds;                                /// OpenAsset bounding box

  Animation[] animations;                       /// Animations
  uint animation = 0;                           /// Current Animation
  Mesh[string] meshes;                          /// Meshes
  AMat[] materials;                             /// Materials

  BoundingBox box = null;                       /// Bounding Box
  bool skipBoundingBox = false;                 /// Do we compute boundingboxes ?
  bool window = false;                          /// ImGui window displayed?

  @nogc this() nothrow {
    uid = guid;
    atomicOp!"+="(guid, 1);
  }

  /** Allocate vertex, index, and instance buffers */
  void buffer(ref App app, VkCommandBuffer cmdBuffer) {
    if(app.trace) SDL_Log("Buffering: %s", toStringz(geometry()));
    if(!buffers[VERTEX] && vertices.length > 0) {
      buffers[VERTEX] = app.toGPU(vertices, vertexBuffer, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
      app.nameGeometryBuffer(vertexBuffer, "VERTEX", geometry());
    }
    if(!buffers[INDEX] && indices.length > 0){
      buffers[INDEX] = app.toGPU(indices, indexBuffer, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
      app.nameGeometryBuffer(indexBuffer, "INDEX", geometry());
    }
    if(!buffers[INSTANCE] && instances.length > 0){
      buffers[INSTANCE] = app.toGPU(instances, instanceBuffer, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
      app.nameGeometryBuffer(instanceBuffer, "INSTANCE", geometry());
    }
  }

  bool isVisible = true;                            /// Boolean flag
  bool inFrustum = true;                            /// Boolean flag
  bool isSelectable = true;                         /// Boolean flag
  bool deAllocate = false;                          /// Boolean flag
  bool instancedMesh = false;                       /// When true, meshdef is per-instance relative index
  bool castShadow = true;                           /// Boolean flag

  bool[3] buffers = [false, false, false];          /// Boolean flag
  @property @nogc bool isBuffered() nothrow { return(buffers[VERTEX] && buffers[INDEX] && buffers[INSTANCE]); }
  @nogc void markDirty() nothrow { buffers[INSTANCE] = false; }
  @nogc void initInstanced(string delegate() name, DrawInstance[] initial = []) nothrow {
    instancedMesh = true;
    instances = initial;
    geometry = name;
  }

  /** Set position of instance from object.instances by p */
  @nogc void position(float[3] p, uint instance = 0) nothrow {
    import matrix : position;
    assert(instance <  instances.length, "No such instance");
    instances[instance] = position(instances[instance], p);
    markDirty();
  }

  @nogc float[3] position(uint instance = 0) nothrow {
    import matrix : position;
    assert(instance <  instances.length, "No such instance");
    return(position(instances[instance]));
  }

  /** Rotate instance from object.instances by r */
  @nogc void rotate(float[3] r, uint instance = 0) nothrow {
    import matrix : rotate;
    assert(instance <  instances.length, "No such instance");
    instances[instance] = rotate(instances[instance], r);
    markDirty();
  }

  /** Scale instance from object.instances by s */
  @nogc void scale(float[3] s, uint instance = 0) nothrow {
    import matrix : scale;
    assert(instance <  instances.length, "No such instance");
    instances[instance] = scale(instances[instance], s);
    markDirty();
  }

  VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;  /// Vulkan render topology (selects Pipeline)

  void delegate(SDL_Event e) onMouseEnter;
  void delegate(SDL_Event e) onMouseExit;
  void delegate(SDL_Event e) onMouseDown;
  void delegate(SDL_Event e) onMouseUp;
  void delegate(SDL_Event e) onMouseOver;
  void delegate(SDL_Event e) onMouseMove;
  void delegate(float dt) onFrame;
  void delegate() onTick;
  string delegate() geometry;
}

void logDraw(T)(ref App app, ref T object) {
  if(!app.trace) return;
  foreach(ref inst; object.instances) {
    for(uint m = inst.meshdef[0]; m < inst.meshdef[1]; m++) { if(m < app.meshes.length){ logMesh(m, app.meshes[m], toStringz(object.geometry())); } }
  }
}

void bufferGeometries(ref App app, ref VkCommandBuffer cmd){
  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.objects[x].instances.length == 0) continue;
    if(app.objects[x].box is null || !app.objects[x].isBuffered) app.objects[x].computeBoundingBox(app.trace);
    if(app.showBounds && !app.objects[x].box.isBuffered) app.objects[x].box.buffer(app, cmd);
    if(!app.objects[x].isBuffered){ app.objects[x].buffer(app, cmd); app.shadows.dirty = true; }
  }
}

/** Set different types of textures on an object */
void setTexture(T)(T object, string name, aiTextureType tt) {
  if(object.materials.length == 0) {
    object.materials.length = 1;
    object.materials[0] = AMat(name, [tt: TexureInfo(name)]);
  } else { object.materials[0].textures[tt] = TexureInfo(name); }
  foreach(ref mesh; object.meshes) { mesh.mid = 0; }
}

void texture(T)(T object, string name, string mname = "") { object.setTexture(name, aiTextureType_DIFFUSE); }
void bumpmap(T)(T object, string name, string mname = "") { object.setTexture(name, aiTextureType_NORMALS); }
void opacity(T)(T object, string name, string mname = "") { object.setTexture(name, aiTextureType_OPACITY); }

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
  object.fence = app.fences[app.syncIndex].renderInFlight;
  app.bufferDeletionQueue.add((bool force){
    if(force || vkGetFenceStatus(app.device, object.fence) == VK_SUCCESS) { app.cleanup(object); return(true); }
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
  for (uint x = 0; x < geometry.vertices.length; x++) { geometry.vertices[x].color = color; }
  geometry.buffers[VERTEX] = false;
}

/** Render a Geometry to app.scenePass.commands[i] */
void draw(T)(ref App app, ref T object, size_t i) {
  if(!object.isBuffered()) return;
  app.logDraw(object);

  VkDeviceSize[] offsets = [0];
  auto cmd = app.scenePass.commands[i];

  vkCmdBindVertexBuffers(cmd, VERTEX, 1, &object.vertexBuffer.vb, &offsets[0]);
  vkCmdBindVertexBuffers(cmd, INSTANCE, 1, &object.instanceBuffer.vb, &offsets[0]);
  vkCmdBindIndexBuffer(cmd, object.indexBuffer.vb, 0, VK_INDEX_TYPE_UINT32);

  vkCmdDrawIndexed(cmd, cast(uint)object.indexBuffer.size / uint.sizeof, cast(uint)object.instances.length, 0, 0, 0);
  if(app.trace) SDL_Log("DRAW[%s]: DONE", toStringz(object.geometry()));
}

/** Render a Geometry to app.shadows.commands[i] */
void shadow(ref App app, Geometry object, size_t i) {
  if(object.vertexBuffer.vb == null || object.instanceBuffer.vb == null || object.indexBuffer.vb == null) return;
  if(app.trace) SDL_Log("SHADOW[%s]: %d instances", toStringz(object.geometry()), object.instances.length);
  VkDeviceSize[] offsets = [0];
  auto cmd = app.shadows.renderPass.commands[i];

  vkCmdBindVertexBuffers(cmd, VERTEX, 1, &object.vertexBuffer.vb, &offsets[0]);
  vkCmdBindVertexBuffers(cmd, INSTANCE, 1, &object.instanceBuffer.vb, &offsets[0]);
  vkCmdBindIndexBuffer(cmd, object.indexBuffer.vb, 0, VK_INDEX_TYPE_UINT32);

  vkCmdDrawIndexed(cmd, cast(uint)object.indexBuffer.size / uint.sizeof, cast(uint)object.instances.length, 0, 0, 0);
  if(app.trace) SDL_Log("SHADOW[%s]: DONE", toStringz(object.geometry()));
}
