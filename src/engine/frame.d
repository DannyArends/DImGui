/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : recordRenderCommandBuffer;
import imgui : recordImGuiCommandBuffer;
import uniforms : updateRenderUBO;
import descriptor : updateDescriptorSet;
import compute : updateComputeDescriptorSet, recordComputeCommandBuffer;

void renderFrame(ref App app){
  if(app.verbose) SDL_Log("renderFrame");
  VkSemaphore computeComplete  = app.sync[app.syncIndex].computeComplete;
  VkSemaphore imageAcquired    = app.sync[app.syncIndex].imageAcquired;
  VkSemaphore renderComplete   = app.sync[app.syncIndex].renderComplete;

  // --- Phase 1: Acquire Image & Wait for CPU-GPU Sync for current frame in flight ---
  if(app.verbose) SDL_Log("Phase 1: Acquire Image & Wait for CPU-GPU Sync for current frame in flight");
  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.syncIndex].computeInFlight, true, uint.max));
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.syncIndex].computeInFlight));

  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.syncIndex].renderInFlight, true, uint.max));
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.syncIndex].renderInFlight));

  app.bufferDeletionQueue.flush();

  auto err = vkAcquireNextImageKHR(app.device, app.swapChain, uint.max, imageAcquired, null, &app.frameIndex);
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);

  //SDL_Log("Frame[%d]: S:%d, F:%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);

  // --- Phase 2: Prepare & Submit Compute Work ---
  if(app.verbose) SDL_Log("Phase 2: Prepare & Submit Compute Work");
  app.updateComputeDescriptorSet([app.compute.shaders[0]], app.compute.set, app.syncIndex);
  //app.updateComputeUBO(app.syncIndex);

  app.recordComputeCommandBuffer(app.syncIndex);

  VkSubmitInfo submitComputeInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount : 1,
    pCommandBuffers : &app.compute.commandBuffer[app.syncIndex],
    signalSemaphoreCount : 1,
    pSignalSemaphores : &computeComplete
  };

  enforceVK(vkQueueSubmit(app.queue, 1, &submitComputeInfo, app.fences[app.syncIndex].computeInFlight));

  // --- Phase 3: Prepare & Submit Graphics & ImGui Work ---
  if(app.verbose) SDL_Log("Phase 3: Prepare & Submit Graphics & ImGui Work");

  app.updateDescriptorSet(app.syncIndex);
  //The above line should become: app.updateComputeDescriptorSet(app.shaders, app.descriptorSet, app.syncIndex);
  app.updateRenderUBO(app.syncIndex);

  app.recordRenderCommandBuffer(app.syncIndex);
  app.recordImGuiCommandBuffer(app.syncIndex);

  VkCommandBuffer[] submitCommandBuffers = [ app.renderBuffers[app.syncIndex], app.imguiBuffers[app.syncIndex] ];

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
  
  enforceVK(vkQueueSubmit(app.queue, 1, &submitInfo, app.fences[app.syncIndex].renderInFlight));
  if(app.verbose) SDL_Log("Done renderFrame");
}

void presentFrame(ref App app) {
  if(app.verbose) SDL_Log("presentFrame");
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
  if(app.verbose) SDL_Log("Done presentFrame");
}

