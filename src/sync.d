// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

import includes;

import application : App;
import vkdebug : enforceVK;

struct SyncObjects {
  uint MAX_FRAMES_IN_FLIGHT = 2; // ImageCount
  uint currentFrame; // SemaphoreIndex
  VkFence[] imagesInFlight;
  VkSemaphore[] imageAvailableSemaphores;
  VkSemaphore[] renderFinishedSemaphores;
  VkFence[] inFlightFences;
}

void createSyncObjects(ref App app) {
  SDL_Log("creating SyncObjects");
  app.synchronization.imagesInFlight.length = app.swapchain.swapChainImages.length;
  for (size_t i = 0; i < app.synchronization.imagesInFlight.length; i++) {
    app.synchronization.imagesInFlight[i] = null;
  }

  app.synchronization.imageAvailableSemaphores.length = app.synchronization.MAX_FRAMES_IN_FLIGHT;
  app.synchronization.renderFinishedSemaphores.length = app.synchronization.MAX_FRAMES_IN_FLIGHT;
  app.synchronization.inFlightFences.length = app.synchronization.MAX_FRAMES_IN_FLIGHT;

  VkSemaphoreCreateInfo semaphoreInfo = { sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
  VkFenceCreateInfo fenceInfo = { sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags: VK_FENCE_CREATE_SIGNALED_BIT };
  
  for (size_t i = 0; i < app.synchronization.MAX_FRAMES_IN_FLIGHT; i++) {
    enforceVK(vkCreateSemaphore(app.dev, &semaphoreInfo, null, &app.synchronization.imageAvailableSemaphores[i]));
    enforceVK(vkCreateSemaphore(app.dev, &semaphoreInfo, null, &app.synchronization.renderFinishedSemaphores[i])); 
    enforceVK(vkCreateFence(app.dev, &fenceInfo, null, &app.synchronization.inFlightFences[i]));
  }
  SDL_Log("Finished creating SyncObjects");
}

