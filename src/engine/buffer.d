/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : beginSingleTimeCommands, endSingleTimeCommands;
import descriptor : Descriptor;
import validation : nameVulkanObject;

struct StageBuffer {
  VkBuffer sb = null;            /// Vulkan Staging Buffer pointer
  VkDeviceMemory sbM = null;     /// Vulkan Staging Buffer memory pointer
  uint frame;                    /// Frame to complete before destoying the buffer
  VkDeviceSize size = 0;         /// Current actual data size in bytes
  VkDeviceSize capacity = 0;     /// Actual allocated size in bytes
  void* data;                    /// Pointer to mapped data
}

struct GeometryBuffer {
  VkBuffer vb = null;            /// Vulkan Buffer pointer
  VkDeviceMemory vbM = null;     /// Vulkan Buffer memory pointer
  StageBuffer staging;           /// Staging buffer for the GeometryBuffer
  alias staging this;
}

void nameGeometryBuffer(ref App app, GeometryBuffer buffer, string type, string name){
  app.nameVulkanObject(buffer.vb, toStringz("["~type~"-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
  app.nameVulkanObject(buffer.vbM, toStringz("["~type~"-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
  app.nameVulkanObject(buffer.sb, toStringz("["~type~"-STAGE-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
  app.nameVulkanObject(buffer.sbM, toStringz("["~type~"-STAGE-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
}

void destroyGeometryBuffers(ref App app, GeometryBuffer buffer) {
  if(buffer.sbM) vkUnmapMemory(app.device, buffer.sbM);
  if(buffer.sb) vkDestroyBuffer(app.device, buffer.sb, app.allocator);
  if(buffer.sbM) vkFreeMemory(app.device, buffer.sbM, app.allocator);

  if(buffer.vb) vkDestroyBuffer(app.device, buffer.vb, app.allocator);
  if(buffer.vbM) vkFreeMemory(app.device, buffer.vbM, app.allocator);
}

void deAllocate(T)(ref App app, T dst, Descriptor descriptor){
  for(uint i = 0; i < app.framesInFlight; i++) {
    vkUnmapMemory(app.device, dst[descriptor.base].memory[i]);
    vkFreeMemory(app.device, dst[descriptor.base].memory[i], app.allocator);
    vkDestroyBuffer(app.device, dst[descriptor.base].buffers[i], app.allocator);
  }
  dst.remove(descriptor.base);
}

uint findMemoryType(VkPhysicalDevice physicalDevice, uint typeFilter, VkMemoryPropertyFlags properties) {
  VkPhysicalDeviceMemoryProperties memoryProperties;
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memoryProperties);
  for (uint i = 0; i < memoryProperties.memoryTypeCount; i++) {
    if (typeFilter && (memoryProperties.memoryTypes[i].propertyFlags & properties) == properties) { return i; }
  }
  assert(0, "Failed to find suitable memory type");
}

@nogc bool hasStencilComponent(VkFormat format) nothrow {
  return format == VK_FORMAT_D32_SFLOAT_S8_UINT  || 
         format == VK_FORMAT_D24_UNORM_S8_UINT || 
         format == VK_FORMAT_D16_UNORM_S8_UINT;
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
  if(app.trace) SDL_Log("Buffer %p [size=%d] created, allocated, and bound", (*buffer), size);
}

void updateBuffer(ref App app, ref GeometryBuffer buffer, VkCommandBuffer cmdBuffer) {
  if(app.trace) SDL_Log("updateBuffer");
  VkBufferCopy copyRegion = { size : buffer.size };
  vkCmdCopyBuffer(cmdBuffer, buffer.sb, buffer.vb, 1, &copyRegion);
}

void copyBufferToImage(ref App app, VkCommandBuffer commandBuffer, VkBuffer buffer, VkImage image, uint width, uint height) {
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

  if(app.trace) SDL_Log("copyBufferToImage buffer[%p] to image[%p] %dx%d", buffer, image, width, height);
  vkCmdCopyBufferToImage(commandBuffer, buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
}

/** Create Vulkan buffer and memory pointer and transfer the array of objects into the GPU memory
 */
bool toGPU(T)(ref App app, T[] objects, ref GeometryBuffer buffer, VkCommandBuffer cmdBuffer, VkBufferUsageFlags usage, 
              VkMemoryPropertyFlagBits properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
  VkDeviceSize requiredSize = cast(uint)(objects[0].sizeof * objects.length);
  if(app.trace) SDL_Log("toGPU: Transfering %d x %d = %d bytes", objects[0].sizeof, objects.length, requiredSize);

  // Check if we need to allocate a new buffer or resize the current buffer
  if(requiredSize > buffer.capacity) {
    if (buffer.vb != null) { // The old buffer was not empty
      auto oldbuffer = buffer;
      oldbuffer.frame = app.totalFramesRendered + app.framesInFlight;
      app.bufferDeletionQueue.add((bool force){ // Add the old buffer to the buffer deletion queue
        if (force || (app.totalFramesRendered >= oldbuffer.frame)){ app.destroyGeometryBuffers(oldbuffer); return(true); }
        return(false);
      });
    }
    VkDeviceSize newCapacity = requiredSize > 0 ? (requiredSize * 2) : 256;
    buffer = GeometryBuffer();
    app.createBuffer(&buffer.sb, &buffer.sbM, newCapacity);
    app.createBuffer(&buffer.vb, &buffer.vbM, newCapacity, usage, properties);
    vkMapMemory(app.device, buffer.sbM, 0, newCapacity, 0, &buffer.data);
    buffer.capacity = newCapacity;
  }
  memcpy(buffer.data, cast(void*)objects, requiredSize);
  buffer.size = requiredSize;
  app.updateBuffer(buffer, cmdBuffer);

  if(app.trace) SDL_Log("toGPU: Buffer[%p]: %d bytes uploaded to GPU", buffer.vb, requiredSize);
  return(true);
}

