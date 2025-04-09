import includes;

import matrix : mat4;

enum VERTEX_BUFFER_BIND_ID = 0;
const INSTANCE_BUFFER_BIND_ID = 1;

struct Vertex {
  float[3] pos = [0.0f, 0.0f, 0.0f];
  float[2] texCoord = [0.0f, 1.0f];
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];
  float[3] normal = [0.0f, 1.0f, 0.0f];

  @nogc static VkVertexInputBindingDescription[2] getBindingDescription() nothrow {
    VkVertexInputBindingDescription[2] bindingDescription = [
      { binding: VERTEX_BUFFER_BIND_ID, stride: Vertex.sizeof, inputRate: VK_VERTEX_INPUT_RATE_VERTEX },
      { binding: INSTANCE_BUFFER_BIND_ID, stride: mat4.sizeof, inputRate: VK_VERTEX_INPUT_RATE_INSTANCE }
    ];
    return bindingDescription;
  }

  @nogc static VkVertexInputAttributeDescription[8] getAttributeDescriptions() nothrow {
    VkVertexInputAttributeDescription[8] attributeDescriptions = [
      { binding: VERTEX_BUFFER_BIND_ID, location: 0, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.pos.offsetof },
      { binding: VERTEX_BUFFER_BIND_ID, location: 1, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Vertex.color.offsetof },
      { binding: VERTEX_BUFFER_BIND_ID, location: 2, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.normal.offsetof },
      { binding: VERTEX_BUFFER_BIND_ID, location: 3, format: VK_FORMAT_R32G32_SFLOAT, offset: Vertex.texCoord.offsetof },

      { binding: INSTANCE_BUFFER_BIND_ID, location: 4, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: 0 },
      { binding: INSTANCE_BUFFER_BIND_ID, location: 5, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: 4 * float.sizeof },
      { binding: INSTANCE_BUFFER_BIND_ID, location: 6, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: 8 * float.sizeof },
      { binding: INSTANCE_BUFFER_BIND_ID, location: 7, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: 12 * float.sizeof }
    ];
    return attributeDescriptions;
  }
};


