import engine;

void renderFrame(ref App app, ImDrawData* drawData, VkClearValue clear = VkClearValue(VkClearColorValue([0.45f, 0.55f, 0.60f, 1.00f]))){
  VkSemaphore imageAcquired  = app.sync[app.syncIndex].imageAcquired;
  VkSemaphore renderComplete = app.sync[app.syncIndex].renderComplete;

  auto err = vkAcquireNextImageKHR(app.device, app.swapChain, uint.max, imageAcquired, null, &app.frameIndex);
  if (app.verbose) SDL_Log("Frame[%d]: S:%d, F:%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);

  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.frameIndex], true, uint.max));
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.frameIndex]));
  enforceVK(vkResetCommandPool(app.device, app.commandPool[app.frameIndex], 0));

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  enforceVK(vkBeginCommandBuffer(app.commandBuffers[app.frameIndex], &commandBufferInfo));

  VkRect2D renderArea = { extent: { width: app.width, height: app.height } };

  VkRenderPassBeginInfo renderPassInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass : app.renderpass,
    framebuffer : app.swapChainFramebuffers[app.frameIndex],
    renderArea : renderArea,
    clearValueCount : 1,
    pClearValues : &clear
  };
  vkCmdBeginRenderPass(app.commandBuffers[app.frameIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
  
  ImGui_ImplVulkan_RenderDrawData(drawData, app.commandBuffers[app.frameIndex], null);
  
  vkCmdEndRenderPass(app.commandBuffers[app.frameIndex]);

  enforceVK(vkEndCommandBuffer(app.commandBuffers[app.frameIndex]));
  
  VkCommandBuffer[] submitCommandBuffers = [ app.commandBuffers[app.frameIndex] ];

  VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

  VkSubmitInfo submitInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    waitSemaphoreCount : 1,
    pWaitSemaphores : &imageAcquired,
    pWaitDstStageMask : &waitStage,

    commandBufferCount : cast(uint)submitCommandBuffers.length,
    pCommandBuffers : &submitCommandBuffers[0],
    signalSemaphoreCount : 1,
    pSignalSemaphores : &renderComplete
  };
  
  enforceVK(vkQueueSubmit(app.queue, 1, &submitInfo, app.fences[app.frameIndex]));
}

void presentFrame(ref App app){
  VkSemaphore renderComplete = app.sync[app.syncIndex].renderComplete;
  VkPresentInfoKHR info = {
    sType : VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    waitSemaphoreCount : 1,
    pWaitSemaphores : &renderComplete,
    swapchainCount : 1,
    pSwapchains : &app.swapChain,
    pImageIndices : &app.frameIndex,
  };
  auto err = vkQueuePresentKHR(app.queue, &info);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  app.syncIndex = (app.syncIndex + 1) % app.sync.length; // Now we can use the next set of semaphores
}

void destroyFrameData(ref App app) {
  for (uint i = 0; i < app.sync.length; i++) {
    vkDestroySemaphore(app.device, app.sync[i].imageAcquired, app.allocator);
    vkDestroySemaphore(app.device, app.sync[i].renderComplete, app.allocator);
  }
  for (uint i = 0; i < app.imageCount; i++) {
    vkDestroyFence(app.device, app.fences[i], app.allocator);
    vkFreeCommandBuffers(app.device, app.commandPool[i], 1, &app.commandBuffers[i]);
    vkDestroyCommandPool(app.device, app.commandPool[i], app.allocator);
    vkDestroyImageView(app.device, app.swapChainImageViews[i], app.allocator);
    vkDestroyFramebuffer(app.device, app.swapChainFramebuffers[i], app.allocator);
  }
  if(app.renderpass) vkDestroyRenderPass(app.device, app.renderpass, app.allocator);
  if(app.swapChain) vkDestroySwapchainKHR(app.device, app.swapChain, app.allocator);
  app.swapChain = null;
}
