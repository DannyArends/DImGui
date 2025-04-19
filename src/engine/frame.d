import engine;

import imgui : renderGUI;
import uniforms : updateUniformBuffer;

void renderFrame(ref App app){
  VkSemaphore imageAcquired  = app.sync[app.syncIndex].imageAcquired;
  VkSemaphore renderComplete = app.sync[app.syncIndex].renderComplete;

  auto err = vkAcquireNextImageKHR(app.device, app.swapChain, uint.max, imageAcquired, null, &app.frameIndex);
  //if (app.verbose) SDL_Log("Frame[%d]: S:%d, F:%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);

  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.frameIndex], true, uint.max));
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.frameIndex]));
  enforceVK(vkResetCommandBuffer(app.imguiBuffers[app.frameIndex], 0));

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  enforceVK(vkBeginCommandBuffer(app.imguiBuffers[app.frameIndex], &commandBufferInfo));

  VkRect2D renderArea = { extent: { width: app.camera.width, height: app.camera.height } };

  VkRenderPassBeginInfo renderPassInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass : app.imguiPass,
    framebuffer : app.swapChainFramebuffers[app.frameIndex],
    renderArea : renderArea,
    clearValueCount : app.clearValue.length,
    pClearValues : &app.clearValue[0]
  };
  vkCmdBeginRenderPass(app.imguiBuffers[app.frameIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);

  // Render UI
  ImDrawData* drawData = app.renderGUI();
  ImGui_ImplVulkan_RenderDrawData(drawData, app.imguiBuffers[app.frameIndex], null);

  vkCmdEndRenderPass(app.imguiBuffers[app.frameIndex]);

  enforceVK(vkEndCommandBuffer(app.imguiBuffers[app.frameIndex]));

  VkCommandBuffer[] submitCommandBuffers = [ app.renderBuffers[app.frameIndex], app.imguiBuffers[app.frameIndex] ];

  VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

  // Update the uniform buffer in case anything has changed
  app.updateUniformBuffer(app.frameIndex);

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

