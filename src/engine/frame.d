/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : recordRenderCommandBuffer;
import imgui : recordImGuiCommandBuffer;
import uniforms : updateRenderUBO;
import descriptor : updateDescriptorSet;
import compute : updateComputeDescriptorSet, updateComputeUBO, recordComputeCommandBuffer;

void renderFrame(ref App app){
  VkSemaphore computeComplete  = app.sync[app.syncIndex].computeComplete;
  VkSemaphore imageAcquired    = app.sync[app.syncIndex].imageAcquired;
  VkSemaphore renderComplete   = app.sync[app.syncIndex].renderComplete;

  auto err = vkAcquireNextImageKHR(app.device, app.swapChain, uint.max, imageAcquired, null, &app.frameIndex);
  //if (app.verbose) SDL_Log("Frame[%d]: S:%d, F:%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);

  /// Compute Submission
  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.frameIndex].computeInFlight, true, uint.max));
  app.updateComputeDescriptorSet(app.frameIndex);
  app.updateComputeUBO(app.frameIndex);
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.frameIndex].computeInFlight));
  app.recordComputeCommandBuffer(app.frameIndex);

  VkSubmitInfo submitComputeInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount : 1,
    pCommandBuffers : &app.compute.buffer[app.frameIndex],
    signalSemaphoreCount : 1,
    pSignalSemaphores : &computeComplete
  };

  enforceVK(vkQueueSubmit(app.queue, 1, &submitComputeInfo, app.fences[app.frameIndex].computeInFlight));

  /// Graphics & ImGui Submission
  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.frameIndex].renderInFlight, true, uint.max));
  app.updateDescriptorSet(app.frameIndex);
  app.updateRenderUBO(app.frameIndex);
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.frameIndex].renderInFlight));
  app.recordRenderCommandBuffer(app.frameIndex);
  app.recordImGuiCommandBuffer(app.frameIndex);

  VkCommandBuffer[] submitCommandBuffers = [ app.renderBuffers[app.frameIndex], app.imguiBuffers[app.frameIndex] ];

  VkSemaphore[] waitSemaphores = [ computeComplete, imageAcquired ];
  VkPipelineStageFlags[] waitStages = [ VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT ];

  VkSubmitInfo submitInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    waitSemaphoreCount : 2,
    pWaitSemaphores : &waitSemaphores[0],
    pWaitDstStageMask : &waitStages[0],

    commandBufferCount : cast(uint)submitCommandBuffers.length,
    pCommandBuffers : &submitCommandBuffers[0],
    signalSemaphoreCount : 1,
    pSignalSemaphores : &renderComplete
  };
  
  enforceVK(vkQueueSubmit(app.queue, 1, &submitInfo, app.fences[app.frameIndex].renderInFlight));
}

void presentFrame(ref App app) {
  if(app.rebuild) return;
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

