/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Sync
 */
struct Sync {
  VkSemaphore computeComplete;
  VkSemaphore imageAcquired;
  VkSemaphore renderComplete;
}

struct Fence {
  VkFence renderInFlight;
  VkFence computeInFlight;
}

/** Create Vulkan synchronization objects
 */
void createSyncObjects(ref App app) {
  app.sync.length = app.framesInFlight;
  app.fences.length = app.framesInFlight;
  if(app.verbose) SDL_Log("createSyncObjects: Semaphores:%d, Fences: %d", app.sync.length, app.fences.length);

  VkSemaphoreCreateInfo semaphoreInfo = { sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
  for (size_t i = 0; i < app.sync.length; i++) {
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].computeComplete));
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].imageAcquired));
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].renderComplete));
  }
  if(app.verbose) SDL_Log("Done vkCreateSemaphore");

  for (size_t i = 0; i < app.fences.length; i++) {
    VkFenceCreateInfo fenceInfo = { sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags: VK_FENCE_CREATE_SIGNALED_BIT };
    enforceVK(vkCreateFence(app.device, &fenceInfo, null, &app.fences[i].renderInFlight));
    enforceVK(vkCreateFence(app.device, &fenceInfo, null, &app.fences[i].computeInFlight));
  }
  if(app.verbose) SDL_Log("Done vkCreateFence");
  app.frameDeletionQueue.add((){
    app.bufferDeletionQueue.flush(); // Make sure we flush the buffers using the old fences
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkDestroySemaphore(app.device, app.sync[i].computeComplete, app.allocator);
      vkDestroySemaphore(app.device, app.sync[i].imageAcquired, app.allocator);
      vkDestroySemaphore(app.device, app.sync[i].renderComplete, app.allocator);

      vkDestroyFence(app.device, app.fences[i].renderInFlight, app.allocator);
      vkDestroyFence(app.device, app.fences[i].computeInFlight, app.allocator);
    }
  });
}

