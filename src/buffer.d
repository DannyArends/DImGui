import includes;
import application : App;
import commands : beginSingleTimeCommands, endSingleTimeCommands;
import vkdebug : enforceVK;

@nogc bool hasStencilComponent(VkFormat format) nothrow {
  return format == VK_FORMAT_D32_SFLOAT_S8_UINT || format == VK_FORMAT_D24_UNORM_S8_UINT;
}

uint findMemoryType(App app, uint typeFilter, VkMemoryPropertyFlags properties) {
  VkPhysicalDeviceMemoryProperties memProperties;
  vkGetPhysicalDeviceMemoryProperties(app.physicalDevices[app.selected], &memProperties);
  for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
    if (typeFilter & (1 << i) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) { return i; }
  }
  assert(0, "failed to find suitable memory type");
}

void copyBuffer(ref App app, VkBuffer srcBuffer, VkBuffer dstBuffer, VkDeviceSize size) {
  VkCommandBuffer commandBuffer = app.beginSingleTimeCommands();
  VkBufferCopy copyRegion = { size: size };
  vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);
  app.endSingleTimeCommands(commandBuffer);
}

void createBuffer(ref App app, 
                  VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, 
                  VkBuffer* buffer, VkDeviceMemory* bufferMemory) {
  VkBufferCreateInfo bufferInfo = {
    sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    size: size,
    usage: usage,
    sharingMode: VK_SHARING_MODE_EXCLUSIVE
  };

  enforceVK(vkCreateBuffer(app.dev, &bufferInfo, null, buffer));

  VkMemoryRequirements memRequirements;
  vkGetBufferMemoryRequirements(app.dev, (*buffer), &memRequirements);

  VkMemoryAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: memRequirements.size,
    memoryTypeIndex: app.findMemoryType(memRequirements.memoryTypeBits, properties)
  };

  enforceVK(vkAllocateMemory(app.dev, &allocInfo, null, bufferMemory));
  vkBindBufferMemory(app.dev, (*buffer), (*bufferMemory), 0);
  //SDL_Log("Buffer [size=%d] created, allocated, and bound", size);
}
