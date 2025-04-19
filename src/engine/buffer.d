// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

import engine;

import commands : beginSingleTimeCommands, endSingleTimeCommands;

uint findMemoryType(VkPhysicalDevice physicalDevice, uint typeFilter, VkMemoryPropertyFlags properties) {
  VkPhysicalDeviceMemoryProperties memoryProperties;
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memoryProperties);
  for (uint i = 0; i < memoryProperties.memoryTypeCount; i++) {
    if (typeFilter & (1 << i) && (memoryProperties.memoryTypes[i].propertyFlags & properties) == properties) { return i; }
  }
  assert(0, "Failed to find suitable memory type");
}

@nogc bool hasStencilComponent(VkFormat format) nothrow {
  return format == VK_FORMAT_D32_SFLOAT_S8_UINT || format == VK_FORMAT_D24_UNORM_S8_UINT;
}

void createBuffer(App app, VkBuffer* buffer, VkDeviceMemory* bufferMemory, VkDeviceSize size, 
                  VkBufferUsageFlags usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT, 
                  VkMemoryPropertyFlags properties = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) {
  VkBufferCreateInfo bufferInfo = {
    sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    size: size,
    usage: usage,
    sharingMode: VK_SHARING_MODE_EXCLUSIVE
  };

  enforceVK(vkCreateBuffer(app.device, &bufferInfo, null, buffer));

  VkMemoryRequirements memoryRequirements;
  vkGetBufferMemoryRequirements(app.device, (*buffer), &memoryRequirements);

  VkMemoryAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: memoryRequirements.size,
    memoryTypeIndex: app.physicalDevice.findMemoryType(memoryRequirements.memoryTypeBits, properties)
  };

  enforceVK(vkAllocateMemory(app.device, &allocInfo, null, bufferMemory));
  vkBindBufferMemory(app.device, (*buffer), (*bufferMemory), 0);
  if(app.verbose) SDL_Log("Buffer %p [size=%d] created, allocated, and bound", (*buffer), size);
}

void copyBuffer(ref App app, VkBuffer srcBuffer, VkBuffer dstBuffer, VkDeviceSize size) {
  VkCommandBuffer commandBuffer = app.beginSingleTimeCommands();
  VkBufferCopy copyRegion = { size: size };
  vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);
  app.endSingleTimeCommands(commandBuffer);
}

void copyBufferToImage(ref App app, VkBuffer buffer, VkImage image, uint width, uint height) {
  VkCommandBuffer commandBuffer = app.beginSingleTimeCommands();
  VkOffset3D imageOffset = { 0, 0, 0 };
  VkExtent3D imageExtent = { width, height, 1 };

  VkImageSubresourceLayers imageSubresource = {
    aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
    mipLevel: 0,
    baseArrayLayer: 0,
    layerCount: 1
  };
  
  VkBufferImageCopy region = {
    bufferOffset: 0,
    bufferRowLength: 0,
    bufferImageHeight: 0,
    imageSubresource: imageSubresource,
    imageOffset: imageOffset,
    imageExtent: imageExtent
  };

  if(app.verbose) SDL_Log("copyBufferToImage buffer[%p] to image[%p] %dx%d", buffer, image, width, height);
  vkCmdCopyBufferToImage(commandBuffer, buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
  app.endSingleTimeCommands(commandBuffer);
}

void toGPU(T)(ref App app, T[] object, VkBuffer* buffer, VkDeviceMemory* memory, VkBufferUsageFlags usage) {
  uint size = cast(uint)(object[0].sizeof * object.length);
  if(app.verbose) SDL_Log("toGPU: Transfering %d x %d = %d bytes", object[0].sizeof, object.length, size);

  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;
  app.createBuffer(&stagingBuffer, &stagingBufferMemory, size);

  void* data;
  vkMapMemory(app.device, stagingBufferMemory, 0, size, 0, &data);
  memcpy(data, cast(void*)object, size);
  vkUnmapMemory(app.device, stagingBufferMemory);

  auto properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
  app.createBuffer(buffer, memory, size, usage, properties);

  app.copyBuffer(stagingBuffer, (*buffer), size);

  vkDestroyBuffer(app.device, stagingBuffer, app.allocator);
  vkFreeMemory(app.device, stagingBufferMemory, app.allocator);
  if(app.verbose) SDL_Log("toGPU: Buffer[%p]: %d bytes uploaded to GPU", (*buffer), size);
}

