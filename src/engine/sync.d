// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

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
}
