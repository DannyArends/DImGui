/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer, deAllocate, StageBuffer;
import descriptor : Descriptor;
import validation : nameVulkanObject;

struct SSBO {
  VkBuffer[] buffers;
  VkDeviceMemory[] memory;
  void*[] data;
  bool[] dirty;
}

void nameSSBO(ref App app, SSBO ssbo, string name){
  for(uint i = 0; i < ssbo.buffers.length; i++) {
    app.nameVulkanObject(ssbo.buffers[i], toStringz(format("[SSBO-BUF] %s #%d", name, i)), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(ssbo.memory[i], toStringz(format("[SSBO-MEM] %s #%d", name, i)), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
}

void createSSBO(ref App app, ref Descriptor descriptor, uint nObjects = 1000) {
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
    vkMapMemory(app.device, app.buffers[descriptor.base].memory[i], 0, descriptor.size, 0, &app.buffers[descriptor.base].data[i]);
    app.buffers[descriptor.base].dirty[i] = true;
  }
  app.nameSSBO(app.buffers[descriptor.base], descriptor.base);

  app.swapDeletionQueue.add((){
    if(app.verbose) SDL_Log("Deleting SSBO at %s", toStringz(descriptor.base));
    app.deAllocate(app.buffers, descriptor);
  });
}

void writeSSBO(App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet[] dst, ref VkDescriptorBufferInfo[] bufferInfos, uint syncIndex = 0){
  if(app.verbose) SDL_Log("writeSSBO %s = %d (%d x %d)", toStringz(descriptor.base), descriptor.size, descriptor.bytes, descriptor.nObjects);
  bufferInfos ~= VkDescriptorBufferInfo(app.buffers[descriptor.base].buffers[syncIndex], 0, descriptor.size);
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst[syncIndex],
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    descriptorCount: 1,
    pBufferInfo: &bufferInfos[($-1)]
  };
  write ~= set;
}

void updateSSBO(T)(ref App app, VkCommandBuffer cmdBuffer, T[] objects, Descriptor descriptor, uint syncIndex) {
  uint size = cast(uint)(T.sizeof * objects.length);
  if(size == 0) return;
  if(!app.buffers[descriptor.base].dirty[syncIndex]) return;
  memcpy(app.buffers[descriptor.base].data[syncIndex], &objects[0], size);
  app.buffers[descriptor.base].dirty[syncIndex] = false; // TODO: enable dirty
}

