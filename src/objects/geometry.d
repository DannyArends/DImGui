import engine;

import buffer : toGPU;
import matrix : mat4;
import vector : vSub, vAdd, cross, normalize;
import vertex : Vertex, VERTEX_BUFFER_BIND_ID, INSTANCE_BUFFER_BIND_ID;

struct Instance {
  uint tid = 0;
  mat4 matrix = mat4.init;
  alias matrix this;
}

struct Geometry {
  VkBuffer vertexBuffer = null;
  VkDeviceMemory vertexBufferMemory = null;

  VkBuffer indexBuffer = null;
  VkDeviceMemory indexBufferMemory = null;

  VkBuffer instanceBuffer = null;
  VkDeviceMemory instanceBufferMemory = null;

  Vertex[] vertices;
  uint[] indices;
  Instance[] instances = [Instance.init];
  alias instances this;

  void buffer(ref App app) {
    app.toGPU(vertices, &vertexBuffer, &vertexBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    app.toGPU(indices, &indexBuffer, &indexBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    app.toGPU(instances, &instanceBuffer, &instanceBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
  }

  void destroy(ref App app) {
    vkDestroyBuffer(app.device, vertexBuffer, app.allocator);
    vkFreeMemory(app.device, vertexBufferMemory, app.allocator);
    vkDestroyBuffer(app.device, indexBuffer, app.allocator);
    vkFreeMemory(app.device, indexBufferMemory, app.allocator);
    vkDestroyBuffer(app.device, instanceBuffer, app.allocator);
    vkFreeMemory(app.device, instanceBufferMemory, app.allocator);
  }
}

/* Add a vertex to a geometry of the object */
uint addVertex(ref Geometry geometry, const Vertex v) nothrow {
  geometry.vertices ~= v;
  return(cast(uint)(geometry.vertices.length-1));
}

/* Get all the triangle faces of a geometry */
pure uint[3][] faces(const Geometry geometry) nothrow {
  uint[3][] fList;
  if(geometry.indices.length <= 2) return(fList); // Objects (e.g. lines) can have less elements than a triangle 
  fList.length = (geometry.indices.length - 2);
  for (uint i = 0, x = 0; x < (geometry.indices.length - 2); x += 3, i++) {
    fList[i] = [geometry.indices[x], geometry.indices[x+1], geometry.indices[x+2]]; // Add to the faces list
  }
  return(fList);
}

/* Compute normal vectors of a Geometry */
void computeNormals(ref Geometry geometry, bool invert = false) {
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
    SDL_Log("computeNormals %d vertex normals computed\n", geometry.vertices.length);
}

// Draws geometry[j] to buffer[i]
void draw(ref App app, Geometry object, size_t i) {
  VkDeviceSize[] offsets = [0];

  vkCmdBindVertexBuffers(app.renderBuffers[i], VERTEX_BUFFER_BIND_ID, 1, &object.vertexBuffer, &offsets[0]);
  vkCmdBindVertexBuffers(app.renderBuffers[i], INSTANCE_BUFFER_BIND_ID, 1, &object.instanceBuffer, &offsets[0]);
  vkCmdBindIndexBuffer(app.renderBuffers[i], object.indexBuffer, 0, VK_INDEX_TYPE_UINT32);

  vkCmdBindDescriptorSets(app.renderBuffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipeline.pipelineLayout, 0, 1, &app.descriptorSet, 0, null);
  if(app.verbose) SDL_Log("DRAW: %d instances", object.instances.length);
  vkCmdDrawIndexed(app.renderBuffers[i], cast(uint)object.indices.length, cast(uint)object.instances.length, 0, 0, 0);
}

