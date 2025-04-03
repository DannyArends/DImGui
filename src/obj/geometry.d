import std.conv : to;

import includes;

import application : App;
import matrix : mat4;
import vertex : Vertex, VERTEX_BUFFER_BIND_ID, INSTANCE_BUFFER_BIND_ID;
import pushconstant : PushConstant;

struct GeometryInstanceData { // Holds instance specific offset data
  mat4 offset = mat4.init;
};

struct Geometry {
  // Vulkan vertex, index and indices bufferhandles
  VkBuffer vertexBuffer = null;
  VkDeviceMemory vertexBufferMemory = null;

  VkBuffer indexBuffer = null;
  VkDeviceMemory indexBufferMemory = null;

  VkBuffer instanceBuffer = null;
  VkDeviceMemory instanceBufferMemory = null;

  // Push constants
  int texture = 0;  // Texture
  mat4 filemodel = mat4.init; // Model is there to correct for file format up/orientation differences (3DS, MTL, WaveFront)

  // Vertices, indices and instances
  Vertex[] vertices;
  uint[] indices;
  GeometryInstanceData[] instances = [GeometryInstanceData.init]; 

  Geometry* next; // TODO: unused
}

// Draws geometry[j] to buffer[i]
void draw(ref App app, size_t i, size_t j) {
  VkDeviceSize[] offsets = [0];

  PushConstant pc = {
    oId: to!int(j),
    tId: app.geometry[j].texture,
    model: app.geometry[j].filemodel
  };
  vkCmdPushConstants(app.commandBuffers[i], app.pipeline.pipelineLayout, 
                     VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, 
                     PushConstant.sizeof, &pc);

  vkCmdBindVertexBuffers(app.commandBuffers[i], VERTEX_BUFFER_BIND_ID, 1, &app.geometry[j].vertexBuffer, &offsets[0]);
  vkCmdBindVertexBuffers(app.commandBuffers[i], INSTANCE_BUFFER_BIND_ID, 1, &app.geometry[j].instanceBuffer, &offsets[0]);

  vkCmdBindIndexBuffer(app.commandBuffers[i], app.geometry[j].indexBuffer, 0, VK_INDEX_TYPE_UINT32);

  vkCmdBindDescriptorSets(app.commandBuffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipeline.pipelineLayout, 0, 1, &app.descriptor.descriptorSets[app.geometry[j].texture], 0, null);

  vkCmdDrawIndexed(app.commandBuffers[i], cast(uint)app.geometry[j].indices.length, cast(uint)app.geometry[j].instances.length, 0, 0, 0);
}
