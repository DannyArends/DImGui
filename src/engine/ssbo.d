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
}

void createSSBO(ref App app, Descriptor descriptor, uint size = 4 * 1024) {
  if(app.verbose) SDL_Log("createSSBO at %s, size = %d", descriptor.base, size);
  app.buffers[descriptor.base] = SSBO();
  app.buffers[descriptor.base].buffers.length = app.framesInFlight;
  app.buffers[descriptor.base].memory.length = app.framesInFlight;

  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.buffers[descriptor.base].buffers[i], &app.buffers[descriptor.base].memory[i], size, 
                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  }

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete SSBO at %s", descriptor.base);
    for(uint i = 0; i < app.framesInFlight; i++) {
      vkDestroyBuffer(app.device, app.buffers[descriptor.base].buffers[i], app.allocator);
      vkFreeMemory(app.device, app.buffers[descriptor.base].memory[i], app.allocator);
    }
  });
}
