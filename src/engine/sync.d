/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import validation : nameVulkanObject;

/** Sync
 */
struct Sync {
  VkSemaphore computeComplete;
  VkSemaphore imageAcquired;
  VkSemaphore renderComplete;
}

struct Fence {
  VkFence renderInFlight;
  VkFence computeInFlight;
}

/** Create Vulkan synchronization objects
 */
void createSyncObjects(ref App app) {
  app.sync.length = app.framesInFlight;
  app.fences.length = app.framesInFlight;
  if(app.verbose) SDL_Log("createSyncObjects: Semaphores:%d, Fences: %d", app.sync.length, app.fences.length);

  VkSemaphoreCreateInfo semaphoreInfo = { sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
  for (size_t i = 0; i < app.sync.length; i++) {
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].computeComplete));
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].imageAcquired));
    enforceVK(vkCreateSemaphore(app.device, &semaphoreInfo, null, &app.sync[i].renderComplete));
    app.nameVulkanObject(app.sync[i].computeComplete, toStringz(format("[SEMAPHORE] computeComplete #%d",i)), VK_OBJECT_TYPE_SEMAPHORE);
    app.nameVulkanObject(app.sync[i].imageAcquired, toStringz(format("[SEMAPHORE] imageAcquired #%d",i)), VK_OBJECT_TYPE_SEMAPHORE);
    app.nameVulkanObject(app.sync[i].renderComplete, toStringz(format("[SEMAPHORE] renderComplete #%d",i)), VK_OBJECT_TYPE_SEMAPHORE);
  }
  if(app.verbose) SDL_Log("Done vkCreateSemaphore");

  for (size_t i = 0; i < app.fences.length; i++) {
    VkFenceCreateInfo fenceInfo = { sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags: VK_FENCE_CREATE_SIGNALED_BIT };
    enforceVK(vkCreateFence(app.device, &fenceInfo, null, &app.fences[i].renderInFlight));
    enforceVK(vkCreateFence(app.device, &fenceInfo, null, &app.fences[i].computeInFlight));
    app.nameVulkanObject(app.fences[i].renderInFlight, toStringz(format("[FENCE] renderInFlight #%d",i)), VK_OBJECT_TYPE_FENCE);
    app.nameVulkanObject(app.fences[i].computeInFlight, toStringz(format("[FENCE] computeInFlight #%d",i)), VK_OBJECT_TYPE_FENCE);
  }
  if(app.verbose) SDL_Log("Done vkCreateFence");
  app.swapDeletionQueue.add((){
    app.bufferDeletionQueue.flush(true); // Make sure we flush the buffers using the old fences
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkDestroySemaphore(app.device, app.sync[i].computeComplete, app.allocator);
      vkDestroySemaphore(app.device, app.sync[i].imageAcquired, app.allocator);
      vkDestroySemaphore(app.device, app.sync[i].renderComplete, app.allocator);

      vkDestroyFence(app.device, app.fences[i].renderInFlight, app.allocator);
      vkDestroyFence(app.device, app.fences[i].computeInFlight, app.allocator);
    }
  });
}

void insertWriteBarrier(ref VkCommandBuffer cmdBuffer, VkBuffer buffer, VkDeviceSize size = VK_WHOLE_SIZE) {
  VkBufferMemoryBarrier writeBarrier = {
      sType : VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      srcAccessMask : VK_ACCESS_SHADER_WRITE_BIT, // Previous stage (e.g., compute shader writing to pOut)
      dstAccessMask : VK_ACCESS_TRANSFER_READ_BIT,  // Access for the copy operation
      buffer : buffer,
      size : size                    // Size of the affected region
  };

  vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 1, &writeBarrier, 0, null);
}

void insertReadBarrier(ref VkCommandBuffer cmdBuffer, VkBuffer buffer, VkDeviceSize size = VK_WHOLE_SIZE) {
  VkBufferMemoryBarrier readBarrier = {
      sType : VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      srcAccessMask : VK_ACCESS_TRANSFER_READ_BIT, // Previous stage (e.g., compute shader writing to pOut)
      dstAccessMask : VK_ACCESS_SHADER_WRITE_BIT,  // Access for the copy operation
      buffer : buffer,
      size : size                    // Size of the affected region
  };

  vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, null, 1, &readBarrier, 0, null);
}

