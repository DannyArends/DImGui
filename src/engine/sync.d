/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

void createSyncObjects(ref App app) {
  app.sync.length = app.imageCount + 1;
  app.fences.length = app.imageCount;
  if(app.verbose) SDL_Log("createSyncObjects: Semaphores:%d, Fences: %d", app.sync.length, app.fences.length);

  VkSemaphoreCreateInfo semaphoreInfo = { sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
  for (size_t i = 0; i < app.sync.length; i++) {
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].imageAcquired));
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].renderComplete));
  }
  if(app.verbose) SDL_Log("Done vkCreateSemaphore");

  for (size_t i = 0; i < app.fences.length; i++) {
    VkFenceCreateInfo fenceInfo = { sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags: VK_FENCE_CREATE_SIGNALED_BIT };
    enforceVK(vkCreateFence(app.device, &fenceInfo, null, &app.fences[i]));
  }
  if(app.verbose) SDL_Log("Done vkCreateFence");
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.sync.length; i++) {
      vkDestroySemaphore(app.device, app.sync[i].imageAcquired, app.allocator);
      vkDestroySemaphore(app.device, app.sync[i].renderComplete, app.allocator);
    }
    for (uint i = 0; i < app.imageCount; i++) {
      vkDestroyFence(app.device, app.fences[i], app.allocator);
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.imguiBuffers[i]);
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.renderBuffers[i]);
      vkDestroyImageView(app.device, app.swapChainImageViews[i], app.allocator);
      vkDestroyFramebuffer(app.device, app.swapChainFramebuffers[i], app.allocator);
    }
  });
}
