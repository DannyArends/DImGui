/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

import matrix : mat4;
import geometry : Instance;

enum { VERTEX = 0, INSTANCE = 1, INDEX = 2}

/** Vertex Structure
 */
struct Vertex {
  float[3] position = [0.0f, 0.0f, 0.0f];     /// Vertex position
  float[2] texCoord = [0.0f, 1.0f];           /// Vertex texture coordinates
  float[4] color = [1.0f, 1.0f, 1.0f, 1.0f];  /// Vertex color
  float[3] normal = [0.0f, 1.0f, 0.0f];       /// Vertex normal

  @nogc static VkVertexInputBindingDescription[2] getBindingDescription() nothrow {
    VkVertexInputBindingDescription[2] bindingDescription = [
      { binding: VERTEX, stride: Vertex.sizeof, inputRate: VK_VERTEX_INPUT_RATE_VERTEX },
      { binding: INSTANCE, stride: Instance.sizeof, inputRate: VK_VERTEX_INPUT_RATE_INSTANCE }
    ];
    return bindingDescription;
  }

  @nogc static VkVertexInputAttributeDescription[9] getAttributeDescriptions() nothrow {
    VkVertexInputAttributeDescription[9] attributeDescriptions = [
      { binding: VERTEX, location: 0, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.position.offsetof },
      { binding: VERTEX, location: 1, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Vertex.color.offsetof },
      { binding: VERTEX, location: 2, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.normal.offsetof },
      { binding: VERTEX, location: 3, format: VK_FORMAT_R32G32_SFLOAT, offset: Vertex.texCoord.offsetof },

      { binding: INSTANCE, location: 4, format: VK_FORMAT_R8_SINT, offset: 0 },
      { binding: INSTANCE, location: 5, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof },
      { binding: INSTANCE, location: 6, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 4 * float.sizeof },
      { binding: INSTANCE, location: 7, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 8 * float.sizeof },
      { binding: INSTANCE, location: 8, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 12 * float.sizeof }
    ];
    return attributeDescriptions;
  }
};


