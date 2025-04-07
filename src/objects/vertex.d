import includes;

enum VERTEX_BUFFER_BIND_ID = 0;

struct Vertex {
  float[3] pos = [0.0f, 0.0f, 0.0f];
  float[2] texCoord = [0.0f, 1.0f];
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];
  float[3] normal = [0.0f, 1.0f, 0.0f];

  @nogc static VkVertexInputBindingDescription[1] getBindingDescription() nothrow {
    VkVertexInputBindingDescription[1] bindingDescription = [
      { binding: VERTEX_BUFFER_BIND_ID, stride: Vertex.sizeof, inputRate: VK_VERTEX_INPUT_RATE_VERTEX }
    ];
    return bindingDescription;
  }

  @nogc static VkVertexInputAttributeDescription[4] getAttributeDescriptions() nothrow {
    VkVertexInputAttributeDescription[4] attributeDescriptions = [
    { binding: VERTEX_BUFFER_BIND_ID, location: 0, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.pos.offsetof },
    { binding: VERTEX_BUFFER_BIND_ID, location: 1, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Vertex.color.offsetof },
    { binding: VERTEX_BUFFER_BIND_ID, location: 2, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.normal.offsetof },
    { binding: VERTEX_BUFFER_BIND_ID, location: 3, format: VK_FORMAT_R32G32_SFLOAT, offset: Vertex.texCoord.offsetof }
    ];
    return attributeDescriptions;
  }
};


