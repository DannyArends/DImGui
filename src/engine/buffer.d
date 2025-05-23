/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : beginSingleTimeCommands, endSingleTimeCommands;

struct GeometryBuffer {
  VkBuffer vb = null;            /// Vulkan Buffer pointer
  VkDeviceMemory vbM = null;     /// Vulkan Buffer memory pointer
  VkBuffer sb = null;            /// Vulkan Staging Buffer pointer
  VkDeviceMemory sbM = null;     /// Vulkan Staging Buffer memory pointer
  VkFence fence;                 /// Fence to complete before destoying the buffer
  uint size = 0;                 /// Size of the buffer
  void* data;                    /// Pointer to mapped data
}

void destroyGeometryBuffers(ref App app, GeometryBuffer buffer) {
  if(buffer.sbM) vkUnmapMemory(app.device, buffer.sbM);
  if(buffer.sb) vkDestroyBuffer(app.device, buffer.sb, null);
  if(buffer.sbM) vkFreeMemory(app.device, buffer.sbM, null);

  if(buffer.vb) vkDestroyBuffer(app.device, buffer.vb, null);
  if(buffer.vbM) vkFreeMemory(app.device, buffer.vbM, null);
}

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

void updateBuffer(ref App app, ref GeometryBuffer buffer, VkDeviceSize size) {
  if(app.verbose) SDL_Log("updateBuffer");
  VkBufferCopy copyRegion = { size: size };
  vkCmdCopyBuffer(app.renderBuffers[app.syncIndex], buffer.sb, buffer.vb, 1, &copyRegion);

  VkBufferMemoryBarrier bufferBarrier = {
    sType : VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
    srcAccessMask : VK_ACCESS_TRANSFER_WRITE_BIT,      // Data written by transfer operation
    dstAccessMask : VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT, // Data read by vertex attributes
    srcQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
    buffer : buffer.vb, // Barrier for your single vertex buffer
    offset : 0,
    size : VK_WHOLE_SIZE // Or app.currentVertexDataSize
  };

  vkCmdPipelineBarrier(
      app.renderBuffers[app.syncIndex],
      VK_PIPELINE_STAGE_TRANSFER_BIT,       // Source stage: Where the write occurred (copy)
      VK_PIPELINE_STAGE_VERTEX_INPUT_BIT,   // Destination stage: Where the read will occur (vertex shader input)
      0, // dependencyFlags
      0, null, // memoryBarriers
      1, &bufferBarrier, // bufferMemoryBarriers
      0, null // imageMemoryBarriers
  );
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

/** Create Vulkan buffer and memory pointer and transfer the array of objects into the GPU memory
 */
bool toGPU(T)(ref App app, T[] objects, ref GeometryBuffer buffer, VkBufferUsageFlags usage, 
              VkMemoryPropertyFlagBits properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
  uint size = cast(uint)(objects[0].sizeof * objects.length);
  if(app.verbose) SDL_Log("toGPU: Transfering %d x %d = %d bytes", objects[0].sizeof, objects.length, size);

  // Check if we need to allocate a new buffer or resize the current buffer
  if(size > buffer.size) {
    if(buffer.size != 0) {
      // Resize, the old buffer was not empty
      auto oldbuffer = buffer;
      oldbuffer.fence = app.fences[app.syncIndex].renderInFlight;
      app.bufferDeletionQueue.add((){ // Add the old buffer to the buffer deletion queue
        if (vkGetFenceStatus(app.device, oldbuffer.fence) == VK_SUCCESS){ app.destroyGeometryBuffers(oldbuffer); return(true); }
        return(false);
      });
      buffer = GeometryBuffer();
    }
    app.createBuffer(&buffer.sb, &buffer.sbM, size);
    app.createBuffer(&buffer.vb, &buffer.vbM, size, usage, properties);
    vkMapMemory(app.device, buffer.sbM, 0, size, 0, &buffer.data);
    buffer.size = size;
  }
  memcpy(buffer.data, cast(void*)objects, size);

  app.updateBuffer(buffer, size);

  if(app.verbose) SDL_Log("toGPU: Buffer[%p]: %d bytes uploaded to GPU", buffer.vb, size);
  return(true);
}

