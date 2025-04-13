import includes;

import matrix : mat4;
import geometry : Instance;

enum VERTEX_BUFFER_BIND_ID = 0;
const INSTANCE_BUFFER_BIND_ID = 1;

struct Vertex {
  float[3] position = [0.0f, 0.0f, 0.0f];
  float[2] texCoord = [0.0f, 1.0f];
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];
  float[3] normal = [0.0f, 1.0f, 0.0f];

  @nogc static VkVertexInputBindingDescription[2] getBindingDescription() nothrow {
    VkVertexInputBindingDescription[2] bindingDescription = [
      { binding: VERTEX_BUFFER_BIND_ID, stride: Vertex.sizeof, inputRate: VK_VERTEX_INPUT_RATE_VERTEX },
      { binding: INSTANCE_BUFFER_BIND_ID, stride: Instance.sizeof, inputRate: VK_VERTEX_INPUT_RATE_INSTANCE }
    ];
    return bindingDescription;
  }

  @nogc static VkVertexInputAttributeDescription[9] getAttributeDescriptions() nothrow {
    VkVertexInputAttributeDescription[9] attributeDescriptions = [
      { binding: VERTEX_BUFFER_BIND_ID, location: 0, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.position.offsetof },
      { binding: VERTEX_BUFFER_BIND_ID, location: 1, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Vertex.color.offsetof },
      { binding: VERTEX_BUFFER_BIND_ID, location: 2, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.normal.offsetof },
      { binding: VERTEX_BUFFER_BIND_ID, location: 3, format: VK_FORMAT_R32G32_SFLOAT, offset: Vertex.texCoord.offsetof },

      { binding: INSTANCE_BUFFER_BIND_ID, location: 4, format: VK_FORMAT_R8_UINT, offset: 0 },
      { binding: INSTANCE_BUFFER_BIND_ID, location: 5, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof },
      { binding: INSTANCE_BUFFER_BIND_ID, location: 6, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 4 * float.sizeof },
      { binding: INSTANCE_BUFFER_BIND_ID, location: 7, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 8 * float.sizeof },
      { binding: INSTANCE_BUFFER_BIND_ID, location: 8, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 12 * float.sizeof }
    ];
    return attributeDescriptions;
  }
};


