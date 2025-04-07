import engine;

import buffer : toGPU;
import vertex : Vertex;

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

