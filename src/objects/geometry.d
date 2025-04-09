import engine;

import buffer : toGPU;
import matrix : mat4;
import vertex : Vertex, VERTEX_BUFFER_BIND_ID, INSTANCE_BUFFER_BIND_ID;

struct Geometry {
  VkBuffer vertexBuffer = null;
  VkDeviceMemory vertexBufferMemory = null;

  VkBuffer indexBuffer = null;
  VkDeviceMemory indexBufferMemory = null;

  VkBuffer instanceBuffer = null;
  VkDeviceMemory instanceBufferMemory = null;

  Vertex[] vertices;
  uint[] indices;
  mat4[] instances = [mat4.init]; 

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

// Draws geometry[j] to buffer[i]
void draw(ref App app, Geometry object, size_t i) {
  VkDeviceSize[] offsets = [0];

  vkCmdBindVertexBuffers(app.renderBuffers[i], VERTEX_BUFFER_BIND_ID, 1, &object.vertexBuffer, &offsets[0]);
  vkCmdBindVertexBuffers(app.renderBuffers[i], INSTANCE_BUFFER_BIND_ID, 1, &object.instanceBuffer, &offsets[0]);
  vkCmdBindIndexBuffer(app.renderBuffers[i], object.indexBuffer, 0, VK_INDEX_TYPE_UINT32);

  vkCmdBindDescriptorSets(app.renderBuffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipeline.pipelineLayout, 0, 1, &app.descriptorSets[i], 0, null);
  SDL_Log("DRAW: %d instances", object.instances.length);
  vkCmdDrawIndexed(app.renderBuffers[i], cast(uint)object.indices.length, cast(uint)object.instances.length, 0, 0, 0);
}

