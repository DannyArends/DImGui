/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : cleanup, nameGeometryBuffer, toGPU, uploadBarrier;
import boundingbox : computeBoundingBox;
import textures : idx;
import mesh : logMesh;
import normals : computeNormals, computeTangents;

shared uint guid = 1;

/** A Geometry that can be rendered */
class Geometry {
  GeometryBuffer!Vertex vertices;               /// Vertices of type Vertex stored on the CPU
  GeometryBuffer!uint indices;                  /// Indices of type uint stored on the CPU
  GeometryBuffer!DrawInstance instances;        /// Instance array

  uint uid;
  Node rootnode;                                /// OpenAsset Root
  string mName;                                 /// OpenAsset name
  MetaData mData;                               /// OpenAsset metaData
  Bounds bounds;                                /// OpenAsset bounding box

  Animation[] animations;                       /// Animations
  uint animation = 0;                           /// Current Animation
  double animTime = 0.0;                        /// ms of animation played, dt-advanced
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
    app.toGPU(vertices, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, "VERTEX", geometry());
    app.toGPU(indices, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT, "INDEX", geometry());
    app.toGPU(instances, cmdBuffer, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, "INSTANCE", geometry());
  }

  bool isVisible = true;                            /// Boolean flag
  bool isOpaque = true;                             /// Boolean flag, alpha-cutout textures: (HSR) pipeline variant
  bool inFrustum = true;                            /// Boolean flag
  bool skipFrustum = false;                         /// Boolean flag
  bool hideInObjectsWindow = false;                 /// Boolean flag
  bool isSelectable = true;                         /// Boolean flag
  bool deAllocate = false;                          /// Boolean flag
  bool instancedMesh = false;                       /// When true, meshdef is per-instance relative index
  bool castShadow = true;                           /// Boolean flag

  @property @nogc bool isStatic() nothrow const { return onFrame is null && onTick is null && isBuffered(); }
  @property @nogc bool isBuffered() nothrow const { return(!vertices.needsBuffer && !indices.needsBuffer && !instances.needsBuffer); }
  @property @nogc bool isDrawable() nothrow const { return(isBuffered && vertices.length > 0 && indices.length > 0 && instances.length > 0); }
  @nogc bool isTopology(VkPrimitiveTopology t) nothrow { return(topology == t); }
  @property @nogc bool hasBoundingBox() nothrow const { return(!(box is null)); }

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
    instances.buffered = false;
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
    instances.buffered = false;
  }

  /** Scale instance from object.instances by s */
  @nogc void scale(float[3] s, uint instance = 0) nothrow {
    import matrix : scale;
    assert(instance <  instances.length, "No such instance");
    instances[instance] = scale(instances[instance], s);
    instances.buffered = false;
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
  @nogc void delegate(bool) nothrow onFrustumUpdate;
  string delegate() geometry;
}

void bufferGeometries(ref App app, ref VkCommandBuffer cmd){
  bool uploaded = false;
  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.objects[x].instances.length == 0) continue;
    if(app.objects[x].box is null || !app.objects[x].isBuffered) app.objects[x].computeBoundingBox(app.trace);
    if(app.showBounds && !app.objects[x].box.isBuffered) { app.objects[x].box.buffer(app, cmd); uploaded = true; }
    if(!app.objects[x].isBuffered){ app.objects[x].buffer(app, cmd); uploaded = true; }
  }
  if(uploaded) app.uploadBarrier(cmd);
}

/** Set different types of textures on an object */
void setTexture(T)(T object, string name, aiTextureType tt) {
  if(object.materials.length == 0) {
    object.materials.length = 1;
    object.materials[0] = AMat(name, [tt: TexureInfo(name)]);
  } else { object.materials[0].textures[tt] = TexureInfo(name); }
  foreach(ref mesh; object.meshes) { mesh.mid = 0; mesh.mat = 0; }
}

void texture(T)(T object, string name, string mname = "") { object.setTexture(name, aiTextureType_DIFFUSE); }
void bumpmap(T)(T object, string name, string mname = "") { object.setTexture(name, aiTextureType_NORMALS); }
void opacity(T)(T object, string name, string mname = "") { object.setTexture(name, aiTextureType_OPACITY); }

/** Euclidean distance between Geometry and Camera */
@nogc float distance(T)(const T object, const Camera camera) nothrow { 
  return euclidean(object.instances[0].getTranslation(), camera.position); 
}

/** Add a vertex to a geometry of the object */
uint addVertex(ref Geometry geometry, const Vertex v) nothrow {
  geometry.vertices ~= v;
  geometry.vertices.buffered = false;
  return(cast(uint)(geometry.vertices.length-1));
}

void setColor(T)(ref T geometry, float[4] color = [1.0f, 0.0f, 0.0f, 1.0f]){
  for (uint x = 0; x < geometry.vertices.length; x++) { geometry.vertices[x].color = color; }
  geometry.vertices.buffered = false;
}

/** Render a Geometry to VkCommandBuffer cmd */
void draw(T)(ref App app, const(T) object, VkCommandBuffer cmd) {
  if(!object.isDrawable()) return;

  VkDeviceSize offset = 0;

  vkCmdBindVertexBuffers(cmd, VERTEX, 1, cast(VkBuffer*)&object.vertices.vb, &offset);
  vkCmdBindVertexBuffers(cmd, INSTANCE, 1, cast(VkBuffer*)&object.instances.vb, &offset);
  vkCmdBindIndexBuffer(cmd, cast(VkBuffer)object.indices.vb, 0, VK_INDEX_TYPE_UINT32);

  vkCmdDrawIndexed(cmd, cast(uint)object.indices.size / uint.sizeof, cast(uint)object.instances.length, 0, 0, 0);
  if(app.trace) SDL_Log("[%s]: DONE", toStringz(object.geometry()));
}
