/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : beginSingleTimeCommands, endSingleTimeCommands;
import deletion : deAllocate;
import validation : nameVulkanObject;

/** A bound GPU buffer: handle + its memory + mapped pointer (data == null, means device-local / unmapped). */
struct GPUAllocation {
  VkBuffer buffer;
  VkDeviceMemory memory;
  void* data;
}

struct GeometryBuffer(T = ubyte) {
  VkBuffer vb = null;            /// Vulkan Buffer pointer
  VkDeviceMemory vbM = null;     /// Vulkan Buffer memory pointer

  VkBuffer sb = null;            /// Vulkan Staging Buffer pointer
  VkDeviceMemory sbM = null;     /// Vulkan Staging Buffer memory pointer

  VkDeviceSize size = 0;         /// Current actual data size in bytes
  VkDeviceSize capacity = 0;     /// Actual allocated size in bytes
  void* data;                    /// Pointer to mapped data - non-null means sbM is mapped

  T[] items = [];
  alias items this;
  void opAssign(T[] rhs) { items = rhs; }

  bool buffered = false;
  @property @nogc bool needsBuffer() nothrow const { return(!buffered && items.length > 0); }
}

void nameGeometryBuffer(T)(ref App app, GeometryBuffer!T buffer, string type, string name){
  app.nameVulkanObject(buffer.vb, toStringz("["~type~"-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
  app.nameVulkanObject(buffer.vbM, toStringz("["~type~"-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
  app.nameVulkanObject(buffer.sb, toStringz("["~type~"-STAGE-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
  app.nameVulkanObject(buffer.sbM, toStringz("["~type~"-STAGE-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
}

@nogc void cleanup(T)(ref App app, ref GeometryBuffer!T buffer) nothrow {
  if(buffer.data) vkUnmapMemory(app.device, buffer.sbM);
  if(buffer.sb) vkDestroyBuffer(app.device, buffer.sb, app.allocator);
  if(buffer.sbM) vkFreeMemory(app.device, buffer.sbM, app.allocator);

  if(buffer.vb) vkDestroyBuffer(app.device, buffer.vb, app.allocator);
  if(buffer.vbM) vkFreeMemory(app.device, buffer.vbM, app.allocator);
  buffer = GeometryBuffer!T();
}

void cleanup(T)(ref App app, ref T object) if(is(T : Geometry)) {
  app.cleanup(object.vertices);
  app.cleanup(object.indices);
  app.cleanup(object.instances);
  if(object.box) app.cleanup(object.box);
}

/** Reap a retired GPU allocation; deAllocate!GPUAllocation finds this via the arg's module. */
@nogc void cleanup(ref App app, GPUAllocation allocation) nothrow {
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

void copyBufferToImage(ref App app, VkCommandBuffer commandBuffer, VkBuffer buffer, VkImage image, uint width, uint height) {
  VkBufferImageCopy region = {
    bufferOffset: 0, bufferRowLength: 0, bufferImageHeight: 0,
    imageSubresource: { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
    imageOffset: { 0, 0, 0 },
    imageExtent: { width, height, 1 }
  };

  if(app.trace) SDL_Log("copyBufferToImage buffer[%p] to image[%p] %dx%d", buffer, image, width, height);
  vkCmdCopyBufferToImage(commandBuffer, buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
}

void copyImageToBuffer(ref App app, VkCommandBuffer commandBuffer, VkImage image, VkBuffer buffer, uint width, uint height) {
  VkBufferImageCopy region = {
    bufferOffset: 0, bufferRowLength: 0, bufferImageHeight: 0,
    imageSubresource: { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
    imageOffset: { 0, 0, 0 },
    imageExtent: { width, height, 1 }
  };
  if(app.trace) SDL_Log("copyImageToBuffer image[%p] to buffer[%p] %dx%d", image, buffer, width, height);
  vkCmdCopyImageToBuffer(commandBuffer, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer, 1, &region);
}

/** Allocate or grow a GeometryBuffer if needed */
bool allocateBuffer(T)(ref App app, ref GeometryBuffer!T buffer, VkBufferUsageFlags usage,
                       VkMemoryPropertyFlagBits properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
  if(app.trace) SDL_Log("allocateBuffer: Transferring %d x %d = %d bytes", T.sizeof, buffer.items.length, T.sizeof * buffer.items.length);
  VkDeviceSize requiredSize = cast(uint)(T.sizeof * buffer.items.length);
  if(requiredSize <= buffer.capacity) return(false);

  VkDeviceSize newCapacity = requiredSize > 0 ? (requiredSize * 2) : 256;
  if(buffer.vb != null) app.deAllocate(buffer);
  app.createBuffer(&buffer.sb, &buffer.sbM, newCapacity);
  enforceVK(vkMapMemory(app.device, buffer.sbM, 0, newCapacity, 0, &buffer.data));
  app.createBuffer(&buffer.vb, &buffer.vbM, newCapacity, usage, properties);
  buffer.capacity = newCapacity;
  return(true);
}

/** Upload CPU data to GPU via staging buffer (caller must issue a transfer→read barrier after batching) */
void uploadBuffer(T)(ref App app, ref GeometryBuffer!T buffer, VkCommandBuffer cmdBuffer) {
  buffer.size = cast(uint)(T.sizeof * buffer.items.length);
  memcpy(buffer.data, cast(void*)buffer.items, buffer.size);
  VkBufferCopy copyRegion = { size : buffer.size };
  vkCmdCopyBuffer(cmdBuffer, buffer.sb, buffer.vb, 1, &copyRegion);
  buffer.buffered = true;
}

/** Single transfer→vertex/index-read barrier covering all uploads in this command buffer */
void uploadBarrier(ref App app, VkCommandBuffer cmdBuffer) {
  VkMemoryBarrier barrier = {
    sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER,
    srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,
    dstAccessMask: VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT | VK_ACCESS_INDEX_READ_BIT,
  };
  vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, 0, 1, &barrier, 0, null, 0, null);
}

/** Allocate if needed then upload — convenience wrapper */
void toGPU(T)(ref App app, ref GeometryBuffer!T buffer, VkCommandBuffer cmdBuffer, VkBufferUsageFlags usage, string type = "", string name = "",
              VkMemoryPropertyFlagBits properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
  if(!buffer.needsBuffer) return;
  if(app.trace) SDL_Log("toGPU: Transferring %d x %d = %d bytes", T.sizeof, buffer.items.length, T.sizeof * buffer.items.length);
  if(app.allocateBuffer(buffer, usage, properties)) app.nameGeometryBuffer(buffer, type, name);
  app.uploadBuffer(buffer, cmdBuffer);
}
