import engine;

VkCommandPool createCommandPool(VkDevice device, uint queueFamilyIndex) {
  VkCommandPool commandPool;

  VkCommandPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: queueFamilyIndex,
    flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  };
  enforceVK(vkCreateCommandPool(device, &poolInfo, null, &commandPool));
  SDL_Log("Commandpool %p at queue %d created", commandPool, poolInfo.queueFamilyIndex);
  return(commandPool);
}

VkCommandBuffer createCommandBuffer(VkDevice device, VkCommandPool commandPool, uint nBuffers = 1) {
  VkCommandBuffer commandBuffer;

  VkCommandBufferAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: commandPool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: nBuffers
  };
  enforceVK(vkAllocateCommandBuffers(device, &allocInfo, &commandBuffer));
  SDL_Log("%d CommandBuffer created for pool %p", allocInfo.commandBufferCount, commandPool);
  return(commandBuffer);
}

void createCommandBuffers(ref App app){
  app.commandPool.length = app.imageCount;
  app.commandBuffers.length = app.imageCount;

  for (uint i = 0; i < app.imageCount; i++) {
    app.commandPool[i] = app.device.createCommandPool(app.queueFamily);
    app.commandBuffers[i] = app.device.createCommandBuffer(app.commandPool[i]);
  }
}

