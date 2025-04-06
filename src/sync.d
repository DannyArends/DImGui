import engine;

void createSyncObjects(ref App app) {
  app.sync.length = app.imageCount + 1;
  app.fences.length = app.imageCount;
  SDL_Log("createSyncObjects, SyncObjects:%d, fences: ", app.sync.length, app.fences.length);

  VkSemaphoreCreateInfo semaphoreInfo = { sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
  for (size_t i = 0; i < app.sync.length; i++) {
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].imageAcquired));
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].renderComplete));
  }
  SDL_Log("Done vkCreateSemaphore");

  for (size_t i = 0; i < app.fences.length; i++) {
    VkFenceCreateInfo fenceInfo = { sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags: VK_FENCE_CREATE_SIGNALED_BIT };
    enforceVK(vkCreateFence(app.device, &fenceInfo, null, &app.fences[i]));
  }
  SDL_Log("Done vkCreateFence");
}
