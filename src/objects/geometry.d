import engine;

import buffer : toGPU;
import vertex : Vertex, VERTEX_BUFFER_BIND_ID;

struct Geometry {
  VkBuffer vertexBuffer = null;
  VkDeviceMemory vertexBufferMemory = null;

  VkBuffer indexBuffer = null;
  VkDeviceMemory indexBufferMemory = null;

  Vertex[] vertices;
  uint[] indices;

  void buffer(ref App app) {
    app.toGPU(vertices, &vertexBuffer, &vertexBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    app.toGPU(indices, &indexBuffer, &indexBufferMemory, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
  }

  void destroy(ref App app) {
    vkDestroyBuffer(app.device, vertexBuffer, app.allocator);
    vkFreeMemory(app.device, vertexBufferMemory, app.allocator);
    vkDestroyBuffer(app.device, indexBuffer, app.allocator);
    vkFreeMemory(app.device, indexBufferMemory, app.allocator);
  }
}

// Draws geometry[j] to buffer[i]
void draw(ref App app, Geometry object, size_t i) {
  VkDeviceSize[] offsets = [0];

  vkCmdBindVertexBuffers(app.renderBuffers[i], VERTEX_BUFFER_BIND_ID, 1, &object.vertexBuffer, &offsets[0]);
  vkCmdBindIndexBuffer(app.renderBuffers[i], object.indexBuffer, 0, VK_INDEX_TYPE_UINT32);

  vkCmdDraw(app.renderBuffers[i], cast(uint)object.indices.length, cast(uint)1, 0, 0);
}

struct Cube {
  Geometry geometry = {
    vertices : [
      Vertex([  0.5f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f,  0.5f,  0.5f ], [  1.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f, -0.0f,  0.5f ], [  1.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f, -0.0f,  0.5f ], [  0.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),

      Vertex([  0.5f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f, -0.0f,  0.5f ], [  1.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f, -0.0f, -0.0f ], [  1.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f,  0.5f, -0.0f ], [  0.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),

      Vertex([  0.5f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f,  0.5f, -0.0f ], [  1.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f,  0.5f, -0.0f ], [  1.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f,  0.5f,  0.5f ], [  0.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),

      Vertex([ -0.0f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f,  0.5f, -0.0f ], [  1.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f, -0.0f, -0.0f ], [  1.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f, -0.0f,  0.5f ], [  0.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),

      Vertex([ -0.0f, -0.0f, -0.0f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f, -0.0f, -0.0f ], [  1.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f, -0.0f,  0.5f ], [  1.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f, -0.0f,  0.5f ], [  0.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),

      Vertex([  0.5f, -0.0f, -0.0f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f, -0.0f, -0.0f ], [  1.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.0f,  0.5f, -0.0f ], [  1.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f,  0.5f, -0.0f ], [  0.0f, 1.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ])
    ],
    indices : [0, 1, 2,   2, 3, 0,      // front
               4, 5, 6,   6, 7, 4,      // right
               8, 9,10,  10,11, 8,      // top
              12,13,14,  14,15,12,      // left
              16,17,18,  18,19,16,      // bottom
              20,21,22,  22,23,20]      // backside
  };

  alias geometry this;
}

