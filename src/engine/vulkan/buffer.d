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

struct GeometryBuffer(T = ubyte) {
  VkBuffer[] vb = null;           /// Per-frame device buffers
  VkDeviceMemory[] vbM = null;    /// Backing memory for each vb
  GPUAllocation[] staging;        /// Host-visible upload staging (released once buffered)
  VkDeviceSize[] size;            /// Bytes uploaded per copy
  VkDeviceSize capacity = 0;      /// Allocated bytes per copy (grow-only)

  PackedArray!T data;             /// CPU-side element store
  alias data this;                /// A GeometryBuffer acts as its element store
  private bool[] dirty;           /// Per-copy upload-needed flag
  bool keepStaging = false;       /// Retain staging after upload (for frequently-updated buffers)

  @property @nogc bool buffered() nothrow const { foreach(d; dirty) if(d) return false; return true; }
  @nogc void invalidate() nothrow { dirty[] = true; }
  @nogc void invalidate(uint idx) nothrow { dirty[idx] = true; }
  @property @nogc bool needsBuffer() nothrow const { return(data.length > 0 && (vb.length == 0 || !buffered)); }
  @property @nogc bool drawable() nothrow const { return(vb.length > 0 && data.length > 0); }
  @nogc uint count(uint idx) nothrow const { return(idx < size.length ? cast(uint)(size[idx] / T.sizeof) : 0); }
  @nogc uint slot(uint sync) nothrow const { return(vb.length ? sync % cast(uint)vb.length : 0); }
}

void nameGeometryBuffer(T)(ref App app, GeometryBuffer!T buffer, string type, string name){
  foreach(i; 0 .. buffer.vb.length) {
    app.nameVulkanObject(buffer.vb[i], toStringz("["~type~"-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(buffer.vbM[i], toStringz("["~type~"-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
  foreach(i; 0 .. buffer.staging.length) {
    app.nameVulkanObject(buffer.staging[i].buffer, toStringz("["~type~"-STAGE-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(buffer.staging[i].memory, toStringz("["~type~"-STAGE-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
}

@nogc void cleanup(T)(ref App app, ref GeometryBuffer!T buffer) nothrow {
  foreach(i; 0 .. buffer.staging.length){ app.cleanup(buffer.staging[i]); }
  foreach(i; 0 .. buffer.vb.length) {
    if(buffer.vb[i]) vkDestroyBuffer(app.device, buffer.vb[i], app.allocator);
    if(buffer.vbM[i]) vkFreeMemory(app.device, buffer.vbM[i], app.allocator);
  }
  buffer = GeometryBuffer!T();
}

void cleanup(T)(ref App app, ref T object) if(is(T : Geometry)) {
  app.cleanup(object.vertices);
  app.cleanup(object.indices);
  app.cleanup(object.instances);
  if(object.box){ app.cleanup(object.box); }
}

uint findMemoryType(VkPhysicalDevice physicalDevice, uint typeFilter, VkMemoryPropertyFlags properties) {
  VkPhysicalDeviceMemoryProperties memoryProperties;
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memoryProperties);
  for (uint i = 0; i < memoryProperties.memoryTypeCount; i++) {
    if ((typeFilter & (1 << i)) && (memoryProperties.memoryTypes[i].propertyFlags & properties) == properties) { return i; }
  }
  assert(0, "Failed to find suitable memory type");
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
  if(buffer.vb.length > 0) { app.deAllocate(buffer); }

  buffer.vb = new VkBuffer[app.framesInFlight];
  buffer.vbM = new VkDeviceMemory[app.framesInFlight];
  buffer.size = new VkDeviceSize[app.framesInFlight];
  buffer.dirty = new bool[app.framesInFlight];
  buffer.staging = new GPUAllocation[app.framesInFlight];

  foreach(i; 0 .. app.framesInFlight) {
    app.createAllocation(buffer.staging[i], cast(uint)newCapacity, false);   // host-visible + mapped
    app.createBuffer(&buffer.vb[i], &buffer.vbM[i], newCapacity, usage, properties);
    buffer.dirty[i] = true;
  }
  buffer.capacity = newCapacity;
  return(true);
}

/** Release a fully-uploaded buffer's host-visible staging; deferred so in-flight copies finish first. */
void releaseStaging(T)(ref App app, ref GeometryBuffer!T buffer) {
  foreach(i; 0 .. buffer.staging.length) { if(buffer.staging[i].buffer) { app.deAllocate(buffer.staging[i]); } }
  buffer.staging = null;
}

/** Collapse device copies to one once all have converged; the extras are freed after in-flight frames drain. */
void shrinkCopies(T)(ref App app, ref GeometryBuffer!T buffer) {
  if(buffer.vb.length <= 1) return;
  VkBuffer[] oldVb = buffer.vb[1 .. $].dup;
  VkDeviceMemory[] oldVbM = buffer.vbM[1 .. $].dup;
  buffer.vb = buffer.vb[0 .. 1];
  buffer.vbM = buffer.vbM[0 .. 1];
  auto deadline = app.totalFramesRendered + app.framesInFlight;
  app.bufferDeletionQueue.add((bool force) @nogc nothrow {
    if(!force && app.totalFramesRendered < deadline) return(false);
    foreach(i; 0 .. oldVb.length) {
      if(oldVb[i])  vkDestroyBuffer(app.device, oldVb[i], app.allocator);
      if(oldVbM[i]) vkFreeMemory(app.device, oldVbM[i], app.allocator);
    }
    return(true);
  });
}

/** (Re)create staging if it was released but the buffer needs uploading again. No-op when present. */
void ensureStaging(T)(ref App app, ref GeometryBuffer!T buffer) {
  if(buffer.staging.length == app.framesInFlight && buffer.staging[0].buffer) return;
  buffer.staging = new GPUAllocation[app.framesInFlight];
  foreach(i; 0 .. app.framesInFlight) { app.createAllocation(buffer.staging[i], cast(uint)buffer.capacity, false); }
}

/** Upload CPU data to GPU via staging buffer (caller must issue a transfer→read barrier after batching) */
void uploadBuffer(T)(ref App app, ref GeometryBuffer!T buffer, VkCommandBuffer cmdBuffer) {
  if(!buffer.dirty[app.syncIndex]) return;
  app.ensureStaging(buffer);                                    // <-- re-create if a static buffer went dirty
  buffer.size[app.syncIndex] = cast(uint)(T.sizeof * buffer.items.length);
  memcpy(buffer.staging[app.syncIndex].data, cast(void*)buffer.items, buffer.size[app.syncIndex]);
  VkBufferCopy copyRegion = { size : buffer.size[app.syncIndex] };
  vkCmdCopyBuffer(cmdBuffer, buffer.staging[app.syncIndex].buffer, buffer.vb[app.syncIndex], 1, &copyRegion);
  buffer.dirty[app.syncIndex] = false;
  if(!buffer.keepStaging && buffer.buffered) app.releaseStaging(buffer);
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
  if(buffer.vb.length > 0 && buffer.vb.length < app.framesInFlight) buffer.capacity = 0;  // a settled (1-copy) buffer went dirty: regrow to framesInFlight
  if(app.allocateBuffer(buffer, usage, properties)) app.nameGeometryBuffer(buffer, type, name);
  app.uploadBuffer(buffer, cmdBuffer);
  if(buffer.buffered && buffer.vb.length > 1) app.shrinkCopies(buffer);   // every copy now holds identical data: keep one, retire the rest
}
