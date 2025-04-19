/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : toGPU;
import camera : Camera;
import matrix : mat4, getTranslation, translate, rotate, scale;
import textures : id;
import vector : vSub, vAdd, cross, normalize, euclidean;
import vertex : Vertex, VERTEX_BUFFER_BIND_ID, INSTANCE_BUFFER_BIND_ID;

/** An instance of a Geometry
 */
struct Instance {
  int tid = -1;
  mat4 matrix = mat4.init;
  alias matrix this;
}

/** A Geometry that can be rendered
 */
struct Geometry {
  VkBuffer vertexBuffer = null;                 /// Vulkan vertex buffer pointer
  VkDeviceMemory vertexBufferMemory = null;     /// Vulkan vertex buffer memory pointer

  VkBuffer indexBuffer = null;                  /// Vulkan index buffer pointer
  VkDeviceMemory indexBufferMemory = null;      /// Vulkan index buffer pointer

  VkBuffer instanceBuffer = null;               /// Vulkan instance buffer pointer
  VkDeviceMemory instanceBufferMemory = null;   /// Vulkan instance buffer pointer

  Vertex[] vertices;                            /// Vertices of type Vertex stored on the CPU
  uint[] indices;                               /// Indices of type uint stored on the CPU
  Instance[] instances = [Instance.init];       /// Instance array
  alias instances this;

  void buffer(ref App app) {
    app.toGPU(vertices, &vertexBuffer, &vertexBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    app.toGPU(indices, &indexBuffer, &indexBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    app.toGPU(instances, &instanceBuffer, &instanceBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    isBuffered = true;
  }

  bool isVisible = true;    /// Boolean flag
  bool isBuffered = false;  /// Boolean flag
  VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;  /// Vulkan render topology (selects Pipeline)
}

/** Set position of instance from object.instances by p */
@nogc void position(ref Geometry object, float[3] p, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  object.instances[instance] = translate(object.instances[instance], p);
}

/** Rotate instance from object.instances by r */
@nogc void rotate(ref Geometry object, float[3] r, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  object.instances[instance] = rotate(object.instances[instance], r);
}

/** Scale instance from object.instances by s */
@nogc void scale(ref Geometry object, float[3] s, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  object.instances[instance] = scale(object.instances[instance], s);
}

/** Set tid for instance from object.instances to Texture name */
@nogc void texture(ref Geometry object, const Texture[] textures, const(char)* name, uint instance = 0) nothrow {
  assert(instance <  object.instances.length, "No such instance");
  object.instances[instance].tid = textures.id(name);
}

/** Euclidean distance between Geometry and Camera */
@nogc float distance(const Geometry object, const Camera camera) nothrow { 
    return euclidean(object.instances[0].getTranslation(), camera.position); 
}

/** deAllocate all GPU buffers */
void deAllocate(ref App app, Geometry object) {
  vkDestroyBuffer(app.device, object.vertexBuffer, app.allocator);
  vkFreeMemory(app.device, object.vertexBufferMemory, app.allocator);
  vkDestroyBuffer(app.device, object.indexBuffer, app.allocator);
  vkFreeMemory(app.device, object.indexBufferMemory, app.allocator);
  vkDestroyBuffer(app.device, object.instanceBuffer, app.allocator);
  vkFreeMemory(app.device, object.instanceBufferMemory, app.allocator);
}

/** Add a vertex to a geometry of the object */
uint addVertex(ref Geometry geometry, const Vertex v) nothrow {
  geometry.vertices ~= v;
  return(cast(uint)(geometry.vertices.length-1));
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
void computeNormals(ref Geometry geometry, bool invert = false, bool verbose = false) {
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
  if(verbose) SDL_Log("computeNormals %d vertex normals computed\n", geometry.vertices.length);
}

/** Render a Geometry to app.renderBuffers[i] */
void draw(ref App app, Geometry object, size_t i) {
  VkDeviceSize[] offsets = [0];

  vkCmdBindPipeline(app.renderBuffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipelines[object.topology].graphicsPipeline);

  vkCmdBindVertexBuffers(app.renderBuffers[i], VERTEX_BUFFER_BIND_ID, 1, &object.vertexBuffer, &offsets[0]);
  vkCmdBindVertexBuffers(app.renderBuffers[i], INSTANCE_BUFFER_BIND_ID, 1, &object.instanceBuffer, &offsets[0]);
  vkCmdBindIndexBuffer(app.renderBuffers[i], object.indexBuffer, 0, VK_INDEX_TYPE_UINT32);

  vkCmdBindDescriptorSets(app.renderBuffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, 
                          app.pipelines[object.topology].pipelineLayout, 0, 1, &app.descriptorSet, 0, null);

  if(app.verbose) SDL_Log("DRAW: %d instances", object.instances.length);
  vkCmdDrawIndexed(app.renderBuffers[i], cast(uint)object.indices.length, cast(uint)object.instances.length, 0, 0, 0);
}

