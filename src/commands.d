import engine;

void createCommandBuffers(ref App app, uint queueFamily){
  app.commandPool.length = app.imageCount;
  app.commandBuffers.length = app.imageCount;

  VkCommandPoolCreateInfo poolInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    flags : VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
    queueFamilyIndex : queueFamily
  };
  for (uint i = 0; i < app.imageCount; i++) {
    enforceVK(vkCreateCommandPool(app.device, &poolInfo, null, &app.commandPool[i]));
    SDL_Log("Command pool %p created", app.commandPool[i]);
    VkCommandBufferAllocateInfo allocInfo = {
      sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      commandPool: app.commandPool[i],
      level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      commandBufferCount: cast(uint) 1
    };
    enforceVK(vkAllocateCommandBuffers(app.device, &allocInfo, &app.commandBuffers[i]));
    SDL_Log("Command buffer with %d buffers created", allocInfo.commandBufferCount);
  }
}
