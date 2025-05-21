/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : draw;

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 */
void recordRenderCommandBuffer(ref App app, uint frameIndex) {
  if(app.verbose) SDL_Log("recordRenderCommandBuffer");

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pInheritanceInfo: null // Optional
  };
  enforceVK(vkBeginCommandBuffer(app.renderBuffers[frameIndex], &beginInfo));
  if(app.verbose) SDL_Log("renderBuffer %d recording", frameIndex);

  VkRect2D renderArea = {
    offset: { x:0, y:0 },
    extent: { width: app.camera.width, height: app.camera.height }
  };

  VkRenderPassBeginInfo renderPassInfo = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: app.renderpass,
    framebuffer: app.swapChainFramebuffers[frameIndex],
    renderArea: renderArea,
    clearValueCount: app.clearValue.length,
    pClearValues: &app.clearValue[0]
  };

  vkCmdBeginRenderPass(app.renderBuffers[frameIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
  if(app.verbose) SDL_Log("Render pass recording to buffer %d", frameIndex);

  if(app.verbose) SDL_Log("Going to draw %d objects to renderBuffer %d", app.objects.length, frameIndex);
  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isBuffered) app.objects[x].buffer(app);
    if(app.objects[x].isVisible) app.draw(app.objects[x], frameIndex);
  }
  vkCmdEndRenderPass(app.renderBuffers[frameIndex]);
  enforceVK(vkEndCommandBuffer(app.renderBuffers[frameIndex]));
  if(app.verbose) SDL_Log("Render pass finished to %d", frameIndex);

}

void createCommandPool(ref App app) {
  VkCommandPool commandPool;

  VkCommandPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: app.queueFamily,
    flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  };
  enforceVK(vkCreateCommandPool(app.device, &poolInfo, null, &app.commandPool));
  app.mainDeletionQueue.add((){ vkDestroyCommandPool(app.device, app.commandPool, app.allocator); });

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

void createImGuiCommandBuffers(ref App app) { 
  app.imguiBuffers = app.device.createCommandBuffer(app.commandPool, app.imageCount, app.verbose);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.imageCount; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.imguiBuffers[i]);
    }
  });
}

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
  if(app.verbose) SDL_Log("createRenderCommandBuffers created %d renderBuffer using commandpool[%p]", app.imageCount, app.commandPool);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.imageCount; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.renderBuffers[i]);
    }
  });
}

