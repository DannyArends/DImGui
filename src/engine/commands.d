import engine;

import geometry : draw;

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

VkCommandBuffer[] createCommandBuffer(VkDevice device, VkCommandPool commandPool, uint nBuffers = 1, bool verbose = false) {
  VkCommandBuffer[] commandBuffer;
  commandBuffer.length = nBuffers;

  VkCommandBufferAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: commandPool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: nBuffers
  };
  enforceVK(vkAllocateCommandBuffers(device, &allocInfo, &(commandBuffer[0])));
  if(verbose) SDL_Log("%d CommandBuffer created for pool %p", allocInfo.commandBufferCount, commandPool);
  return(commandBuffer);
}

void createImGuiCommandBuffers(ref App app) { app.imguiBuffers = app.device.createCommandBuffer(app.commandPool, app.imageCount, app.verbose); }

VkCommandBuffer beginSingleTimeCommands(ref App app) {
  VkCommandBuffer[1] commandBuffer = app.device.createCommandBuffer(app.commandPool, 1, app.verbose);

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  vkBeginCommandBuffer(commandBuffer[0], &beginInfo);
  return commandBuffer[0];
}

void endSingleTimeCommands(ref App app, VkCommandBuffer commandBuffer) {
  vkEndCommandBuffer(commandBuffer);

  VkSubmitInfo submitInfo = {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: &commandBuffer
  };

  vkQueueSubmit(app.queue, 1, &submitInfo, null);
  vkQueueWaitIdle(app.queue);

  vkFreeCommandBuffers(app.device, app.commandPool, 1, &commandBuffer);
}

void createRenderCommandBuffers(ref App app) { 
  app.renderBuffers = app.device.createCommandBuffer(app.commandPool, app.imageCount, app.verbose);
  SDL_Log("createRenderCommandBuffers");
}

void recordRenderCommandBuffer(ref App app) {
  SDL_Log("recordRenderCommandBuffer");
  for (size_t i = 0; i < app.renderBuffers.length; i++) {
    VkCommandBufferBeginInfo beginInfo = {
      sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      pInheritanceInfo: null // Optional
    };
    enforceVK(vkBeginCommandBuffer(app.renderBuffers[i], &beginInfo));
    SDL_Log("Command buffer %d recording", i);

    VkRect2D renderArea = {
      offset: { x:0, y:0 },
      extent: { width: app.width, height: app.height }
    };

    VkClearValue[2] clearValues;
    VkClearColorValue color = { float32: [0.0f, 0.0f, 0.0f, 1.0f] };
    VkClearDepthStencilValue depthStencil =  { depth: 1.0f, stencil: 0 };
    clearValues[0].color = color;
    clearValues[1].depthStencil = depthStencil;

    VkRenderPassBeginInfo renderPassInfo = {
      sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      renderPass: app.renderpass,
      framebuffer: app.swapChainFramebuffers[i],
      renderArea: renderArea,
      clearValueCount: clearValues.length,
      pClearValues: &clearValues[0]
    };

    vkCmdBeginRenderPass(app.renderBuffers[i], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    SDL_Log("Render pass recording to buffer %d", i);
    vkCmdBindPipeline(app.renderBuffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipeline.graphicsPipeline);
    SDL_Log("Going to draw objects");
    for(size_t x = 0; x < app.objects.length; x++) {
      app.draw(app.objects[x], i);
    }
    vkCmdEndRenderPass(app.renderBuffers[i]);
    enforceVK(vkEndCommandBuffer(app.renderBuffers[i]));
    SDL_Log("Render pass finished to %d", i);
  }
}

