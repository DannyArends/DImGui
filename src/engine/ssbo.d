/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer, StageBuffer;
import descriptor : Descriptor;

struct SSBO {
  VkBuffer[] buffers;
  VkDeviceMemory[] memory;
  void*[] data;
}

void createSSBO(ref App app, ref Descriptor descriptor, uint nObjects = 1000) {
  if(app.verbose) SDL_Log("createSSBO at %s, size = %d, objects: %d", descriptor.base, descriptor.bytes, nObjects);
  app.buffers[descriptor.base] = SSBO();
  app.buffers[descriptor.base].data.length = app.framesInFlight;
  app.buffers[descriptor.base].buffers.length = app.framesInFlight;
  app.buffers[descriptor.base].memory.length = app.framesInFlight;

  descriptor.nObjects = nObjects;
  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.buffers[descriptor.base].buffers[i], &app.buffers[descriptor.base].memory[i], descriptor.size, 
                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkMapMemory(app.device, app.buffers[descriptor.base].memory[i], 0, descriptor.size, 0, &app.buffers[descriptor.base].data[i]);
  }

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete SSBO at %s", descriptor.base);
    for(uint i = 0; i < app.framesInFlight; i++) {
      vkUnmapMemory(app.device, app.buffers[descriptor.base].memory[i]);
      vkFreeMemory(app.device, app.buffers[descriptor.base].memory[i], app.allocator);
      vkDestroyBuffer(app.device, app.buffers[descriptor.base].buffers[i], app.allocator);
    }
  });
}

void writeSSBO(App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet[] dst, uint syncIndex = 0){
  auto bufferInfo = new VkDescriptorBufferInfo(app.buffers[descriptor.base].buffers[syncIndex], 0, descriptor.size);
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst[syncIndex],
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    descriptorCount: 1,
    pBufferInfo: bufferInfo
  };
  write ~= set;
}

void updateSSBO(T)(ref App app, VkCommandBuffer cmdBuffer, T[] objects, VkBuffer dst, uint syncIndex) {
  uint size = cast(uint)(T.sizeof * objects.length);
  if(size == 0) return;
  StageBuffer buffer = {
    size : size,
    frame : app.totalFramesRendered + app.framesInFlight
  };

  app.createBuffer(&buffer.sb, &buffer.sbM, buffer.size);
  vkMapMemory(app.device, buffer.sbM, 0, buffer.size, 0, &buffer.data);
  memcpy(buffer.data, &objects[0], buffer.size);
  vkUnmapMemory(app.device, buffer.sbM);

  VkBufferCopy copyRegion = {
    srcOffset : 0, // Offset in source buffer
    dstOffset : 0, // Offset in destination buffer
    size : buffer.size // Size to copy
  };

  vkCmdCopyBuffer(cmdBuffer, buffer.sb, dst, 1, &copyRegion);

  VkBufferMemoryBarrier bufferBarrier = {
      sType : VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      srcAccessMask : VK_ACCESS_TRANSFER_WRITE_BIT, // Data was written by transfer
      dstAccessMask : VK_ACCESS_SHADER_READ_BIT,    // Shader will read it
      srcQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
      dstQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
      buffer : dst, // The SSBO buffer itself
      offset : 0,
      size : VK_WHOLE_SIZE // Barrier applies to the whole buffer
  };

  vkCmdPipelineBarrier(
      cmdBuffer,
      VK_PIPELINE_STAGE_TRANSFER_BIT,    // Source stage: Transfer (copy)
      VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, // Destination stage: Vertex shader reads
      0, // dependencyFlags
      0, null, // memoryBarriers
      1, &bufferBarrier, // bufferMemoryBarriers (our SSBO barrier)
      0, null // imageMemoryBarriers
  );
  app.bufferDeletionQueue.add((bool force){
    if (force || (app.totalFramesRendered >= buffer.frame)){
      vkDestroyBuffer(app.device, buffer.sb, app.allocator);
      vkFreeMemory(app.device, buffer.sbM, app.allocator);
      return(true);
    }
    return(false);
  });
}
