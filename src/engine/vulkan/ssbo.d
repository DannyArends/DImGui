/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer, deAllocate;
import validation : nameVulkanObject;

/** GPU SSBO buffers, memory, data and dirty flags */
struct SSBO {
  VkBuffer[] buffers;
  VkDeviceMemory[] memory;
  void*[] data;
  bool[] dirty;
}

/** CPU+GPU SSBO container with capacity tracking */
struct SSBOList(T) {
  T[] items;
  ulong capacity = 256;
  alias items this;
}

/** Name SSBO buffers and memory for debugging */
void nameSSBO(ref App app, SSBO ssbo, string name){
  for(uint i = 0; i < ssbo.buffers.length; i++) {
    app.nameVulkanObject(ssbo.buffers[i], toStringz(format("[SSBO-BUF] %s #%d", name, i)), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(ssbo.memory[i], toStringz(format("[SSBO-MEM] %s #%d", name, i)), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
}

/** Create GPU SSBO buffer for nObjects */
void createSSBO(ref App app, ref Descriptor descriptor, uint nObjects = 1024) {
  if(app.verbose) SDL_Log("createSSBO at %s, size = %d, objects: %d", toStringz(descriptor.base), descriptor.bytes, nObjects);
  descriptor.nObjects = nObjects;
  if(descriptor.base in app.buffers) return;
  app.buffers[descriptor.base] = SSBO();
  app.buffers[descriptor.base].data.length = app.framesInFlight;
  app.buffers[descriptor.base].buffers.length = app.framesInFlight;
  app.buffers[descriptor.base].memory.length = app.framesInFlight;
  app.buffers[descriptor.base].dirty.length = app.framesInFlight;

  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.buffers[descriptor.base].buffers[i], &app.buffers[descriptor.base].memory[i], descriptor.size, 
                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    enforceVK(vkMapMemory(app.device, app.buffers[descriptor.base].memory[i], 0, descriptor.size, 0, &app.buffers[descriptor.base].data[i]));
    if(app.trace) SDL_Log("createSSBO: %s, nObjects=%d, size=%d", toStringz(descriptor.base), nObjects, descriptor.size);
    app.buffers[descriptor.base].dirty[i] = true;
  }
  app.nameSSBO(app.buffers[descriptor.base], descriptor.base);

  app.swapDeletionQueue.add((){
    if(app.verbose) SDL_Log("Deleting SSBO at %s", toStringz(descriptor.base));
    app.deAllocate(app.buffers, descriptor);
  });
}

/** Create GPU SSBO from container */
void createSSBO(T)(ref App app, ref Descriptor descriptor, ref SSBOList!T container) {
  if(container.length > container.capacity) container.capacity = container.length;
  app.createSSBO(descriptor, cast(uint)container.capacity);
}

/** Upload container data to GPU, grow and rebuild if overflow */
void updateSSBO(T)(ref App app, VkCommandBuffer cmdBuffer, ref SSBOList!T container, Descriptor descriptor, uint syncIndex) {
  uint size = cast(uint)(T.sizeof * container.length);
  if(size == 0) return;
  if(size > descriptor.size) {
    while(container.capacity * T.sizeof < size) container.capacity *= 2;
    app.rebuild = true;
    return;
  }
  if(!app.buffers[descriptor.base].dirty[syncIndex]) return;
  if(app.trace) SDL_Log("updateSSBO: %s syncIndex=%d objects=%d", toStringz(descriptor.base), syncIndex, cast(uint)container.length);
  memcpy(app.buffers[descriptor.base].data[syncIndex], &container[0], size);
  app.buffers[descriptor.base].dirty[syncIndex] = false;
}

