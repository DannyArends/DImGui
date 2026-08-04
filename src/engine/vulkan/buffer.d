/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commandpool : beginSingleTimeCommands, endSingleTimeCommands;
import deletion : deAllocate;

/** A bound GPU buffer: handle + its memory + mapped pointer (data == null, means device-local / unmapped). */
struct GPUAllocation {
  VkBuffer buffer;                /// Buffer handle
  VkDeviceMemory memory;          /// Backing device memory
  void* data;                     /// Mapped pointer (non-null only for host-visible allocations)
}

/** Create (and map, if host-visible) a GPUAllocation at `size`; host-visible copies are zero-filled. */
void createAllocation(ref App app, ref GPUAllocation allocation, uint size, bool deviceLocal, bool concurrent = false) {
  VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  VkMemoryPropertyFlags props = deviceLocal ? VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT : (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  app.createBuffer(&allocation.buffer, &allocation.memory, size, usage, props, concurrent);
  if(!deviceLocal) { enforceVK(vkMapMemory(app.device, allocation.memory, 0, size, 0, &allocation.data)); (cast(ubyte*)allocation.data)[0 .. size] = 0; }
}

/** Reap a retired GPU allocation; deAllocate!GPUAllocation finds this via the arg's module. */
@nogc void cleanup(ref App app, ref GPUAllocation allocation) nothrow {
  if(allocation.data) vkUnmapMemory(app.device, allocation.memory);
  vkDestroyBuffer(app.device, allocation.buffer, app.allocator);
  vkFreeMemory(app.device, allocation.memory, app.allocator);
}

uint findMemoryType(VkPhysicalDevice physicalDevice, uint typeFilter, VkMemoryPropertyFlags properties) {
  VkPhysicalDeviceMemoryProperties memoryProperties;
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memoryProperties);
  for (uint i = 0; i < memoryProperties.memoryTypeCount; i++) {
    if ((typeFilter & (1 << i)) && (memoryProperties.memoryTypes[i].propertyFlags & properties) == properties) { return i; }
  }
  assert(0, "Failed to find suitable memory type");
}

/** Single transfer vertex/index-read barrier covering all uploads in this command buffer */
void uploadBarrier(ref App app, VkCommandBuffer cmdBuffer) {
  VkMemoryBarrier barrier = {
    sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER,
    srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,
    dstAccessMask: VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT | VK_ACCESS_INDEX_READ_BIT,
  };
  vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, 0, 1, &barrier, 0, null, 0, null);
}

@nogc bool hasStencilComponent(VkFormat f) nothrow {
  return(f == VK_FORMAT_D32_SFLOAT_S8_UINT  || f == VK_FORMAT_D24_UNORM_S8_UINT || f == VK_FORMAT_D16_UNORM_S8_UINT);
}

@nogc bool isDepth(VkFormat f) nothrow {
  return(f == VK_FORMAT_D32_SFLOAT || f == VK_FORMAT_D32_SFLOAT_S8_UINT || f == VK_FORMAT_D24_UNORM_S8_UINT);
}

void createBuffer(App app, VkBuffer* buffer, VkDeviceMemory* bufferMemory, VkDeviceSize size, 
                  VkBufferUsageFlags usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT, 
                  VkMemoryPropertyFlags properties = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                  bool concurrent = false) {
  uint[2] queues = [app.queues.graphics.family, app.queues.compute.family];
  bool crossQueue = concurrent && (queues[0] != queues[1]);

  VkBufferCreateInfo bufferInfo = {
    sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    size: size, usage: usage,
    sharingMode: crossQueue ? VK_SHARING_MODE_CONCURRENT : VK_SHARING_MODE_EXCLUSIVE,
    queueFamilyIndexCount: crossQueue ? 2 : 0,
    pQueueFamilyIndices: crossQueue ? &queues[0] : null
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
  if(app.trace) SDL_Log("Buffer %p [size=%d] created, allocated, and bound", (*buffer), size);
}

/** Whole-image color copy region (mip 0, layer 0), shared by the buffer<->image copies. */
@nogc pure VkBufferImageCopy bufferImageCopy(uint width, uint height) nothrow {
  VkBufferImageCopy region = {
    bufferOffset: 0, bufferRowLength: 0, bufferImageHeight: 0,
    imageSubresource: { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
    imageOffset: { 0, 0, 0 },
    imageExtent: { width, height, 1 }
  };
  return region;
}

/** Copy staging buffer -> image (whole image, TRANSFER_DST layout). */
void copyBufferToImage(ref App app, VkCommandBuffer commandBuffer, VkBuffer buffer, VkImage image, uint width, uint height) {
  VkBufferImageCopy region = bufferImageCopy(width, height);
  if(app.trace) SDL_Log("copyBufferToImage buffer[%p] to image[%p] %dx%d", buffer, image, width, height);
  vkCmdCopyBufferToImage(commandBuffer, buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
}

/** Copy image -> staging buffer (whole image, TRANSFER_SRC layout). */
void copyImageToBuffer(ref App app, VkCommandBuffer commandBuffer, VkImage image, VkBuffer buffer, uint width, uint height) {
  VkBufferImageCopy region = bufferImageCopy(width, height);
  if(app.trace) SDL_Log("copyImageToBuffer image[%p] to buffer[%p] %dx%d", image, buffer, width, height);
  vkCmdCopyImageToBuffer(commandBuffer, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer, 1, &region);
}
