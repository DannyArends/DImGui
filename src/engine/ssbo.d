/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer;
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
