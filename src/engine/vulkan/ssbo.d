/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer, deAllocate;
import validation : nameVulkanObject;

/** GPU SSBO: per-copy allocations, per-copy dirty flags, and layout. */
struct SSBO {
  GPUAllocation[] allocations;
  alias allocations this;

  bool[] dirty;
  uint nObjects;
  uint stride;
  bool deviceLocal;

  @property uint size(){ return nObjects * stride; }
}

/** All SSBOs + the per-syncIndex "an SSBO grew, re-point this set" flags. */
struct SSBOStore {
  SSBO[string] ssbos;
  bool[] descriptorsDirty;   // per-syncIndex (length = framesInFlight)
  alias ssbos this;
}

/** CPU+GPU SSBO container with capacity tracking */
struct SSBOList(T) {
  T[] items;
  ulong capacity = 256;
  alias items this;
}

/** Name SSBO buffers and memory for debugging */
void nameSSBO(ref App app, SSBO ssbo, string name){
  for(uint i = 0; i < ssbo.length; i++) {
    app.nameVulkanObject(ssbo[i].buffer, toStringz(format("[SSBO-BUF] %s #%d", name, i)), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(ssbo[i].memory, toStringz(format("[SSBO-MEM] %s #%d", name, i)), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
}

/** Create GPU SSBO buffer for nObjects. copies = per-frame buffer count (0 = app.framesInFlight).
 *  copies < framesInFlight is only safe for deviceLocal buffers ordered by a barrier within a frame;
 *  a host-visible buffer driven by updateSSBO needs framesInFlight copies or the CPU races the GPU. */
void createSSBO(ref App app, const Descriptor d, uint nObjects = 1024, uint copies = 0, bool deviceLocal = false) {
  if(copies == 0) copies = app.framesInFlight;
  if(app.verbose) SDL_Log("createSSBO %s, stride = %d, objects: %d, copies: %d, deviceLocal: %d", toStringz(d.base), d.bytes, nObjects, copies, deviceLocal);
  if(d.base in app.buffers) return;
  app.buffers[d.base] = SSBO();
  app.buffers[d.base].nObjects = nObjects;
  app.buffers[d.base].stride = cast(uint)d.bytes;
  app.buffers[d.base].deviceLocal = deviceLocal;
  app.buffers[d.base].length = app.buffers[d.base].dirty.length = copies;

  VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  VkMemoryPropertyFlags props = deviceLocal ? VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT : (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  for(uint i = 0; i < copies; i++) {
    app.createBuffer(&app.buffers[d.base][i].buffer, &app.buffers[d.base][i].memory, app.buffers[d.base].size, usage, props);
    if(!deviceLocal) enforceVK(vkMapMemory(app.device, app.buffers[d.base][i].memory, 0, app.buffers[d.base].size, 0, &app.buffers[d.base][i].data));
    app.buffers[d.base].dirty[i] = true;
  }
  app.nameSSBO(app.buffers[d.base], d.base);

  app.swapDeletionQueue.add((){
    if(app.verbose) SDL_Log("Deleting SSBO at %s", toStringz(d.base));
    foreach(ref allocation; app.buffers[d.base]) {
      if(allocation.data) vkUnmapMemory(app.device, allocation.memory);
      vkDestroyBuffer(app.device, allocation.buffer, app.allocator);
      vkFreeMemory(app.device, allocation.memory, app.allocator);
    }
    app.buffers.ssbos.remove(d.base);
  });
}

/** Grow an SSBO in place: recreate each copy at the new size, defer-delete the old copies,
 *  remap host-visible data, flag descriptors for a targeted re-point. No swapchain/pipeline touch. */
void growSSBO(ref App app, string base, uint nObjects) {
  bool deviceLocal = app.buffers[base].deviceLocal;
  app.buffers[base].nObjects = nObjects;
  uint size = app.buffers[base].size;

  VkBufferUsageFlags usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  VkMemoryPropertyFlags props = deviceLocal ? VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT : (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

  foreach(i, ref allocation; app.buffers[base]) {
    app.deAllocate(allocation);
    app.createBuffer(&allocation.buffer, &allocation.memory, size, usage, props);
    if(!deviceLocal) enforceVK(vkMapMemory(app.device, allocation.memory, 0, size, 0, &allocation.data));
    app.buffers[base].dirty[i] = true;
  }
  app.nameSSBO(app.buffers[base], base);
  app.buffers.descriptorsDirty[] = true;
  if(app.verbose) SDL_Log("growSSBO %s -> %d objects (%d bytes)", toStringz(base), nObjects, size);
}

/** Create GPU SSBO from container */
void createSSBO(T)(ref App app, const Descriptor descriptor, ref SSBOList!T container) {
  if(container.length > container.capacity) container.capacity = container.length;
  app.createSSBO(descriptor, cast(uint)container.capacity);
}

/** Upload container data to GPU, grow and rebuild if overflow */
void updateSSBO(T)(ref App app, VkCommandBuffer cmdBuffer, ref SSBOList!T container, Descriptor descriptor, uint syncIndex) {
  if(app.buffers[descriptor.base].deviceLocal){ SDL_Log(toStringz(format("Error: Trying to update a device local SSBO: %s", descriptor.base))); return; }
  uint size = cast(uint)(T.sizeof * container.length);
  if(size == 0) return;
  if(size > app.buffers[descriptor.base].size) {
    while(container.capacity * T.sizeof < size) container.capacity *= 2;
    app.growSSBO(descriptor.base, cast(uint)container.capacity);
  }
  if(!app.buffers[descriptor.base].dirty[syncIndex]) return;
  if(app.trace) SDL_Log("updateSSBO: %s syncIndex=%d objects=%d", toStringz(descriptor.base), syncIndex, cast(uint)container.length);
  memcpy(app.buffers[descriptor.base][syncIndex].data, &container[0], size);
  app.buffers[descriptor.base].dirty[syncIndex] = false;
}

