import engine;

void createCommandPool(ref App app) {
  VkCommandPool commandPool;

  VkCommandPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: app.queueFamily,
    flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  };
  enforceVK(vkCreateCommandPool(app.device, &poolInfo, null, &app.commandPool));
  if(app.verbose) SDL_Log("Commandpool %p at queue %d created", app.commandPool, poolInfo.queueFamilyIndex);
}

VkCommandBuffer createCommandBuffer(VkDevice device, VkCommandPool commandPool, uint nBuffers = 1, bool verbose = false) {
  VkCommandBuffer commandBuffer;

  VkCommandBufferAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: commandPool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: nBuffers
  };
  enforceVK(vkAllocateCommandBuffers(device, &allocInfo, &commandBuffer));
  if(verbose) SDL_Log("%d CommandBuffer created for pool %p", allocInfo.commandBufferCount, commandPool);
  return(commandBuffer);
}

void createCommandBuffers(ref App app){
  app.commandBuffers.length = app.imageCount;

  for (uint i = 0; i < app.imageCount; i++) {
    app.commandBuffers[i] = app.device.createCommandBuffer(app.commandPool, 1, app.verbose);
  }
}

